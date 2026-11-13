# Leo Desk Sync System Audit

**Audit branch:** `feature/windows-authoritative-sync`  
**Repository:** `Ravenvd/Leo-Desk`  
**Code baseline:** `641e59e4492845a25db0948ca3ba1996d7c32617`  
**Audit status:** Phase 1 source review; no application code or tests changed  
**Database schema version:** 17

## 1. Executive summary

The current sync implementation is distributed across `SyncManager`, `SyncServer`, `SyncClient`, and entity repositories. UUIDs are generally used as cross-device identity, but conflict policy is implemented separately by each repository and is not consistently Windows-authoritative.

The most important risks are:

1. A server-side upsert can accept an Android payload for an existing UUID when the Windows row is already marked synced. The current protection is largely based on `sync_status == pending`, not an unconditional Windows-authority rule.
2. Several Android pull paths do not force-apply Windows data, so a pending local row can block the canonical Windows copy.
3. Order-number conflicts are currently resolved by allocating the next highest number, not by assigning an alphabetic suffix between existing numbers.
4. Order reconciliation can delete an entire conflicting local order graph, including related bills and invoices. That can destroy a distinct Android-created record.
5. Invoice and bill repositories have additional uniqueness constraints and conflict rules that differ from the agreed UUID-first, preserve-distinct-records policy.
6. Deletion/tombstone support is uneven across entities.
7. Incremental order sync is limited to a recent window of 100 orders.

The existing implementation contains useful building blocks—UUID-based relationships, dependency ordering, acknowledgement, tombstones for selected entities, and overlapping-sync protection—but these need to be unified under one server-authoritative reconciliation policy.

## 2. Sync architecture currently present

| Component | Current responsibility | Audit observation |
|---|---|---|
| `SyncManager` | Coordinates push, pull, acknowledgements and pull-and-replace | 717 lines; contains entity-specific sync sequencing and conflict behaviour |
| `SyncServer` | HTTP API hosted by the Windows machine | 730 lines; routes call repositories directly and make some entity-specific decisions |
| `SyncClient` | HTTP transport and JSON conversion | Numbered entities do not have a consistent canonical-response contract; order is the exception |
| Entity repositories | SQLite reads, writes, pending state and sync upserts | Each repository contains its own conflict policy |
| `DatabaseSchema` | Tables, constraints and migrations | Schema version 17; UUID uniqueness and several natural-key/number uniqueness constraints |

The server exposes these API route families:

- Health and acknowledgement: `/api/health`, `/api/sync/ack`
- Customers: `/api/customers`
- Orders: `/api/orders`
- Invoices: `/api/invoices`
- Bills: `/api/bills`
- Expenses: `/api/expenses`, `/api/expenses/delete`
- Assets: `/api/assets`, `/api/assets/delete`
- Maintenance: `/api/maintenance`, `/api/maintenance/delete`
- Inventory: `/api/inventory`
- Staff: `/api/staff`, `/api/staff/attendance`, `/api/staff/payments`

## 3. Syncable entities, tables and relationships

The current schema creates the following sync-related tables.

| Entity/table | UUID | User-facing number / natural key | Relationships and notes |
|---|---|---|---|
| `customers` | Unique | None | Parent of orders, invoices and bills |
| `orders` | Unique | `order_number` unique | Belongs to customer; has order items; may have one invoice and one bill; inventory activity may reference it |
| `order_items` | Unique | None | Child of order; transferred with order |
| `invoices` | Unique | `invoice_number` unique; `order_uuid` unique | One invoice per order; belongs to order and customer; has invoice items |
| `invoice_items` | Unique | None | Child of invoice; transferred with invoice |
| `bills` | Unique | `bill_number` unique; `order_uuid` unique index | One bill per order when order UUID is present; belongs to customer and optionally order; has bill items |
| `bill_items` | Unique | None | Child of bill; transferred with bill |
| `expenses` | Unique | None | Optional unique `staff_payment_uuid` links salary expense to staff payment |
| `assets` | Unique | `asset_code` unique | Parent of maintenance records |
| `maintenance_records` | Unique | None | Belongs to asset by UUID and local FK |
| `consumables` | Unique | None | Parent of thread spools and inventory activities |
| `thread_spools` | Unique | None | Belongs to consumable |
| `inventory_activities` | Unique | None | Belongs to consumable; optional spool and order references |
| `staff` | Unique | None | Parent of attendance and payments |
| `staff_attendance` | Unique | Unique natural key: `(staff_uuid, attendance_date)` | Belongs to staff |
| `staff_payments` | Unique | None | Belongs to staff; linked to salary expense through `staff_payment_uuid` |

The item tables (`order_items`, `invoice_items`, `bill_items`) are transferred as part of their parent record payload. They do not have independent `sync_status` columns in the current create schema.

### Important database constraints

- Every primary entity UUID is unique.
- `orders.order_number`, `invoices.invoice_number`, `bills.bill_number`, and `assets.asset_code` are unique.
- `invoices.order_id` and `invoices.order_uuid` are unique: one invoice per order.
- Bills have unique indexes on `order_id` and `order_uuid`: one bill per order when linked.
- Attendance has a unique `(staff_uuid, attendance_date)` natural key.
- `expenses.staff_payment_uuid` is unique.
- Foreign keys are enabled by `AppDatabase`. Several parent-child relationships use cascade deletion; invoice/order references use restrictive deletion; inventory activity's optional order/spool references use SET NULL.

These constraints mean collision resolution must be done transactionally and must resolve both UUID identity and all unique natural keys before persistence.

## 4. Existing reconciliation behaviour and risks

### Customers

- Server POST delegates to `CustomerRepository.upsertFromSync`.
- The repository blocks an incoming row only when the same UUID is locally pending and `force` is false.
- If the existing Windows row is synced, an incoming Android payload for that UUID can update it.
- Android pull uses `force: false`, so a pending Android row can prevent a Windows record from being applied.

**Risk:** pending-state protection is not equivalent to Windows authority.

### Orders

- Android pushes pending orders from the 100 most recently updated local orders.
- Server checks UUID and order-number ownership.
- If a new UUID collides with an existing order number, server assigns the next number after the current maximum.
- If an existing UUID's requested number is owned by another UUID, server returns 409.
- `OrderRepository.upsertFromSync` can delete a conflicting order and its bill, invoice, and item graph to free a number.
- Android pull calls this repository with the default `force: false`.

**Risk:** the current max-plus-one allocator does not implement suffix insertion; graph deletion violates the agreed preservation rule; pending local data can block Windows authority.

### Invoices

- Invoice payloads include line items and UUID-based order/customer references.
- Server resolves customer and order UUIDs before calling the invoice repository.
- The repository blocks a pending same-UUID local copy unless forced.
- It does not implement explicit invoice-number collision allocation.
- SQLite requires unique invoice number and one invoice per order.
- Android pull uses `force: false`.

**Risk:** distinct invoice UUIDs that collide on invoice number can fail at the database constraint; same-UUID Android edits can overwrite a synced Windows record on the server; pending Android copies can block Windows pull.

### Bills

- Bill payloads include line items and UUID-based customer/order references.
- The repository uses earliest `createdAt` as the winner for different UUIDs claiming the same order, with UUID as a tie-breaker.
- A bill-number collision against a bill outside the order-conflict set causes the incoming bill to be rejected.
- Losing same-order bills and their items can be deleted.
- A pending same-UUID local copy blocks a pull unless forced.
- Android pull uses `force: false`.

**Risk:** earliest-created-wins is not the agreed Windows-authoritative policy; bill-number collisions are rejected rather than suffix-allocated; Android pending state can block Windows truth.

### Expenses

- Expense tombstones are implemented with `deleted_pending`.
- Server returns tombstones in GET responses and has a delete endpoint.
- Acknowledgement physically removes a tombstone after propagation.
- Same-UUID pending or deleted-pending local rows block a pull unless forced.
- Android pull uses `force: false`.

**Risk:** stale/pending Android state can block Windows data; deletion handling needs to be integrated into a general tombstone policy.

### Assets

- Asset codes are locally generated from SQLite IDs.
- Server allocates an AST code for a new incoming asset and returns only status/UUID, not the canonical asset code.
- For an existing UUID, server retains the Windows asset code.
- Asset pull uses `force: true`.
- Asset code collisions are temporarily displaced to a `PENDING-<uuid>` value before the canonical row is applied.
- Asset tombstones are implemented and acknowledged.

**Risk:** the asset-specific code allocator and response contract are another special-case reconciliation implementation.

### Maintenance

- Maintenance records refer to assets by UUID.
- Push/pull is ordered after assets.
- Maintenance tombstones are implemented.
- Pull uses `force: true`.
- Server upsert blocks a pending Windows record but can update an existing synced UUID from Android.

**Risk:** authority still depends on sync status rather than source authority.

### Inventory

- Inventory sync is a generic map payload distinguished by `record_type`.
- Current record types are `consumables`, `thread_spools`, and `inventory_activities`.
- Push and pull use dependency order: consumables, spools, activities.
- Foreign keys are resolved locally from UUIDs; integer IDs are not intended to cross devices.
- Pull uses `force: true`.
- No corresponding inventory deletion/tombstone route was found in the current sync API.

**Risk:** same-UUID authority is still controlled by pending status in the repository; inventory deletions are not represented through the same tombstone mechanism as expenses/assets/maintenance.

### Staff, attendance and payments

- Staff profiles are pushed/pulled before attendance and payments.
- Attendance uses the natural key `(staff_uuid, attendance_date)` to reconcile same-day duplicates.
- Payments link to staff by UUID.
- Recording a staff payment also creates a salary expense linked by `staff_payment_uuid` in a transaction.
- Staff and attendance/payment pulls use `force: true`.
- `StaffMember` defines a deleted-pending status constant, but the inspected manager push query selects only `pending`; no staff delete route was found.
- Attendance/payment models do not expose a complete tombstone workflow in the inspected sync path.

**Risk:** natural-key conflicts and linked salary expenses need explicit identity rules; deletion coverage is incomplete.

## 5. SyncManager sequence and operational behaviour

Incremental sync currently:

1. Checks server connectivity.
2. Pushes/pulls staff profiles.
3. Pushes/pulls assets.
4. Pushes/pulls customers.
5. Pushes pending orders and pulls the recent Windows order window.
6. Pushes/pulls maintenance.
7. Pushes/pulls inventory in dependency order.
8. Pushes/pulls invoices.
9. Pushes/pulls bills.
10. Pushes/pulls expenses.
11. Pushes/pulls staff attendance and payments.
12. Acknowledges records applied from Windows.

The manager prevents overlapping sync calls by sharing one active Future.

Order sync uses a bounded recent window of 100 records for both pending push selection and Windows pull. This behaviour is covered by existing boundary/window tests, but it means the completeness of incremental sync depends on how records are selected into that window.

`pullAndReplace()` is a separate destructive operation: it downloads the Windows datasets first, then clears local tables and rebuilds them from Windows. Its documentation explicitly warns that pending local changes are discarded. It should remain distinct from normal conflict reconciliation and should require deliberate user intent.

## 6. Existing tests discovered

### Sync tests

- `test/core/sync/sync_manager_test.dart` — broad integration-style coverage for customer, order, invoice, bill, asset, inventory and sync conflict flows. Named cases include pending customer behaviour, bill/item round trips, order graph round trips, stale graph replacement, offline order renumbering, asset-code collision and Windows pending consumable edits.
- `test/core/sync/sync_server_test.dart` — server/client behaviour for customer pending conflicts, assets, inventory records, asset code allocation and maintenance.
- `test/core/sync/order_graph_round_trip_test.dart` — 100/101 order-window boundary and UUID/local-FK round trip.
- `test/core/sync/expense_tombstone_test.dart` — deletion propagation in both directions and prevention of stale Android resurrection for expenses.
- `test/core/sync/offline_recovery_test.dart` — pending expense is retained while Windows is offline and pushed after recovery.
- `test/core/sync/overlapping_sync_test.dart` — concurrent calls share one sync operation.
- `test/core/sync/partial_sync_failure_test.dart` — failed invoice remains pending and retry does not duplicate a successful order.

### Repository/database tests

- `test/features/billing/bill_conflict_resolution_test.dart` — earliest-created bill wins, UUID tie-break, and no deletion of a bill from another order on bill-number collision.
- `test/features/billing/bill_repository_test.dart`
- `test/features/orders/order_repository_test.dart` — includes pending-row protection and basic sync upsert.
- `test/features/customers/customer_repository_test.dart`
- `test/features/customers/repositories/customer_repository_test.dart`
- `test/features/inventory/asset_database_test.dart`
- `test/features/inventory/consumable_repository_test.dart`
- `test/features/inventory/consumables_database_test.dart`
- `test/features/inventory/maintenance_database_test.dart`
- `test/features/staff/staff_attendance_test.dart`
- `test/features/staff/staff_repository_test.dart`
- `test/core/database/migration_test.dart`
- `test/core/database/customer_schema_migration_test.dart`

### Test gaps to close before and during implementation

1. Same UUID, conflicting Android payload versus an existing Windows row: Windows must win for every entity.
2. Distinct UUIDs with the same order, invoice or bill number: both records must survive and the incoming record must receive a canonical suffix.
3. Suffix allocator: A–Z, AA and beyond; occupied suffixes; retries; case/format handling; deterministic insertion order.
4. Multiple offline records colliding with the same base number in different arrival orders.
5. Full order graph preservation, including order items, invoice/items, bill/items and inventory activity references.
6. Same UUID with conflicting child-item UUIDs and content.
7. Idempotent repeated push, pull and acknowledgement.
8. Tombstone propagation and stale-update non-resurrection for every deletable entity.
9. Attendance natural-key collision under Windows authority.
10. Staff-payment and salary-expense consistency.
11. Large datasets beyond the 100-order window.
12. Transaction rollback when number allocation or relationship resolution fails.
13. Legacy/older Android client payload compatibility.

## 7. CI and test execution status

The repository's `.github/workflows/flutter-ci.yml` workflow runs:

- `flutter pub get`
- `flutter analyze`
- `flutter test`

It is configured for pushes to `main`, pull requests targeting `main`, and manual dispatch. A push to this feature branch alone does not trigger that workflow under the current configuration.

**Tests have not been executed as part of this source audit.** The GitHub source inspection does not provide a local Flutter runtime. A baseline run should be performed in a Flutter-enabled checkout before implementation, and the result recorded separately. Do not interpret the existence of tests as evidence that they currently pass.

## 8. Recommended implementation sequence

1. Freeze this audit and capture a real baseline `flutter analyze` and `flutter test` result.
2. Write the sync policy and protocol contract as tests/specification before changing behaviour.
3. Implement and exhaustively test the canonical suffix allocator as a pure unit.
4. Implement the server-side identity/authority reconciliation core.
5. Migrate orders first, with full graph preservation and canonical responses.
6. Migrate invoices and bills with their order/customer constraints.
7. Migrate customers, assets, inventory, maintenance, staff, attendance, payments and expenses.
8. Refactor `SyncManager`, `SyncServer` and `SyncClient` to delegate to the shared policy.
9. Run full integration/regression tests and validate two real databases before release.

## 9. Audit boundary

This document describes the implementation found at baseline commit `641e59e4492845a25db0948ca3ba1996d7c32617`. It is an audit, not a statement that the proposed policy has been implemented. No application source code, database schema, migration or test file was changed during this phase.
