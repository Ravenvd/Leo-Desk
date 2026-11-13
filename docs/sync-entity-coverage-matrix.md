# Sync Entity Coverage Matrix

**Branch:** `feature/windows-authoritative-sync`  
**Audited commit:** `926c62b9860b627375c550384390f0550043e1fb`  
**Audit date:** 2026-11-13  
**Scope:** Existing database tables, repositories, sync manager, HTTP routes, and focused tests.

This document records implementation coverage, not merely whether an entity has a sync endpoint. An entity is considered integrated with the approved Windows-authoritative policy only when the Windows server checks UUID identity first, returns the complete canonical record (and dependent graph where applicable), and the client applies that response before acknowledging success.

## 1. Executive summary

- All four current human-readable numbering namespaces are covered by the canonical Windows allocator: orders, invoices, bills, and assets.
- Customers are integrated with UUID-first Windows-authoritative reconciliation. The user confirmed the full test suite passed after the customer integration.
- Staff profile reconciliation now has a Windows-authoritative repository path, canonical HTTP response, client decoder, and SyncManager application path. New repository, HTTP, and round-trip tests have been added; local verification is pending.
- Several other entities already have push/pull endpoints, but those paths still use legacy boolean acknowledgements or non-authoritative upserts.
- Deletion handling is not compliant with the approved policy yet. In particular, Android deletion requests can currently mark Windows rows as `deleted_pending`, and expense tombstones are physically removed rather than retained as durable authoritative tombstones.
- No additional numbered namespace was identified in the current schema audit.

## 2. Entity coverage

| Entity / table | Existing sync path | Current status | Required work |
|---|---|---|---|
| Customers | `/api/customers` | Integrated | UUID-first transactional reconciliation; complete canonical response; Android applies response |
| Orders and order items | `/api/orders` | Integrated | Canonical order graph, suffix allocator, transactional persistence |
| Invoices and invoice items | `/api/invoices` | Integrated | Canonical invoice graph, suffix allocator, linked-order natural-key validation |
| Bills and bill items | `/api/bills` | Integrated | Canonical bill graph, suffix allocator, linked-order natural-key validation |
| Assets | `/api/assets` | Integrated for live-record reconciliation | Canonical asset response and suffix allocation; deletion path still needs the universal tombstone redesign |
| Expenses | `/api/expenses` | Legacy | Replace boolean acknowledgement with canonical response; UUID-first Windows reconciliation; preserve staff-payment relationship; redesign deletion |
| Maintenance records | `/api/maintenance` | Legacy | Canonical response; UUID-first reconciliation; asset UUID validation; redesign deletion |
| Consumables | `/api/inventory` | Legacy | Canonical response and UUID-first Windows reconciliation |
| Thread spools | `/api/inventory` | Legacy | Canonical response; resolve consumable UUID; reconcile as part of inventory dependency ordering |
| Inventory activities | `/api/inventory` | Legacy | Canonical response; resolve consumable, optional spool and optional order UUIDs; preserve event history |
| Staff profiles | `/api/staff` | Implemented; local verification pending | UUID-first Windows reconciliation and complete canonical response; Android applies the response before acknowledging |
| Staff attendance | `/api/staff/attendance` | Legacy | Canonical response; Windows-authoritative natural-key handling for staff UUID + attendance date |
| Staff payments | `/api/staff/payments` | Legacy | Canonical response; preserve staff UUID and linked salary expense relationship |

## 3. Numbering namespace audit

The current schema and sync policy identify these unique human-readable number fields:

| Entity | Field | Implementation |
|---|---|---|
| Orders | `order_number` | Integrated |
| Invoices | `invoice_number` | Integrated |
| Bills | `bill_number` | Integrated |
| Assets | `asset_code` | Integrated |

No other numbered sync namespace was found in the audited schema. Expenses, maintenance, inventory records, staff, attendance, and staff payments are UUID/natural-key entities, not candidates for the alphabetic number allocator.

## 4. Relationship and natural-key constraints

The sync implementation must preserve these dependencies:

1. **Assets → maintenance records:** maintenance references an asset by UUID. Asset deletion must not silently cascade away maintenance history.
2. **Consumables → thread spools → inventory activities:** spool and activity rows reference their parent consumable by UUID. Activities may also reference a spool and an order.
3. **Staff → attendance and payments:** attendance and payments reference staff by UUID.
4. **Staff payments ↔ expenses:** a salary expense can reference a staff payment through the unique `staff_payment_uuid` relationship. The two sides must remain consistent.
5. **Staff attendance natural key:** the schema enforces one row per `staff_uuid + attendance_date`. A distinct UUID cannot bypass that uniqueness rule or replace the canonical Windows row.
6. **Financial graphs:** order, invoice, and bill parent/child graph rules remain as specified in `sync-policy-and-protocol.md`.

## 5. Deletion audit

The approved deletion contract remains:

- Windows alone creates authoritative tombstones.
- Android submits a deletion request; it does not directly delete or tombstone the Windows record.
- Tombstones propagate to clients and prevent stale resurrection.
- Repeated requests and delivery are idempotent.
- Parent deletion follows explicit dependency and retention rules.
- Tombstones are retained until all required peers have acknowledged them, or an equivalent durable anti-resurrection mechanism exists.

### Current gaps observed

- Expenses currently use `deleted_pending` as a transient state and physically delete rows in `finalizeDeletion` / `applyDeletionFromSync`.
- The expense deletion HTTP endpoint calls `markDeletedPendingByUuid` on Windows in response to the client request.
- Maintenance has a similar deletion endpoint that directly marks the Windows row `deleted_pending`.
- Asset deletion also has a separate request endpoint and must be checked/refactored under the same universal protocol.
- Inventory and staff entities do not yet have a complete universal tombstone/request implementation.
- Existing expense tombstone tests encode the old physical-delete expectation and must be rewritten for authoritative tombstone retention and stale-resurrection prevention.

## 6. Implementation sequence

### Phase A — UUID-based live-record reconciliation

Implement and test one entity family at a time:

1. Staff profiles are implemented; verify them locally, then integrate attendance and payments.
2. Expenses, including the staff-payment relationship.
3. Consumables, thread spools, and inventory activities.
4. Maintenance records, after asset reconciliation is confirmed.

For each family:
- Windows checks UUID before considering incoming fields.
- Same UUID returns the complete existing Windows record unchanged.
- A new UUID is validated and inserted transactionally.
- Natural-key collisions are handled explicitly without replacing another UUID's canonical record.
- The server returns the complete canonical payload.
- The client applies the payload before acknowledging the push.
- Pull always applies Windows canonical values, even over pending Android copies.
- Tests cover same-UUID conflicts, new UUIDs, retries, relationship mapping across different local integer IDs, and failure atomicity.

### Phase B — Universal tombstone protocol

Implement the approved deletion-request, Windows decision, tombstone propagation, acknowledgement/retention, and stale-resurrection prevention rules for all syncable entities. Include dependency-specific deletion tests.

### Phase C — Full verification

- Run the complete Flutter test suite and analyzer on the feature branch.
- Add cross-entity and multi-device sync scenarios.
- Verify interrupted/retried sync, offline edits, deletion while a peer is offline, and app/server restarts.
- Perform real Windows-host / Android-client integration testing.
- Complete backup/restore, migration, compatibility, logging, and release checks.

## 7. Audit limitations

This matrix is based on source inspection of the named feature branch and the repository's current schema, repositories, sync manager, client/server routes, and selected tests. It does not claim that every runtime combination has been exercised. Local Flutter test and analyzer execution must be confirmed by the user; the assistant's GitHub source inspection cannot run those commands against the user's Windows/Android environment.
