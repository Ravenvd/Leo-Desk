# Leo Desk Sync Policy and Protocol Specification

**Branch:** `feature/windows-authoritative-sync`  
**Baseline:** `379fa4e84a7ef00b88cc7c580885d76a423bc333` (Phase 1 audit commit)  
**Status:** Approved policy — order, invoice and bill Windows-authoritative reconciliation implemented; local verification pending  
**Baseline tests:** User reports `flutter analyze` and `flutter test` pass locally on this baseline.

## 1. Purpose

This document converts the agreed Windows-authoritative sync behaviour into explicit rules that can be implemented and tested. It is the contract for the future SyncEngine, entity adapters, SyncServer and SyncClient refactor.

The server running on Windows is the single authority for canonical data. Android is a client that can submit newly created records and receive canonical records. Conflict decisions are never independently made by Android.

## 2. Core invariants

1. **Windows is authoritative.** The Windows database determines the canonical version of an existing record.
2. **UUID defines identity.** Equal UUIDs represent the same logical record; different UUIDs represent different records.
3. **Never discard a distinct record to resolve a number collision.** Both records must survive.
4. **Canonical numbering is server-assigned.** When a distinct incoming record collides with an existing number, Windows allocates the canonical suffix.
5. **Canonical values converge.** Every device stores the exact canonical number returned by Windows, such as `BILL-000012A`.
6. **Idempotency.** Repeating a request for the same UUID must not create another record or allocate another suffix.
7. **Relationship identity is UUID-based.** Local integer database IDs must never be treated as cross-device identifiers.
8. **Atomicity.** A record and its dependent data must be reconciled in a transaction; partial graphs must not be exposed as successfully synced.
9. **One policy implementation.** Server-side SyncEngine owns identity, authority, number and deletion decisions. Repositories persist the decision; they must not implement competing sync conflict policies.
10. **No silent data loss.** A conflict must result in a canonical response or an explicit rejection/error, never silent deletion.

## 3. Identity and authority resolution

For every incoming entity:

| Condition | Required server behaviour |
|---|---|
| No matching UUID exists | Treat as a new record; validate relationships and insert |
| Same UUID exists on Windows | Keep the complete Windows record as canonical; do not apply Android field changes |
| Different UUID owns the requested unique number | Preserve both records; allocate an available suffix to the incoming record |
| Same UUID is retried | Return the already stored canonical record and number; do not allocate again |
| New UUID and no number collision | Preserve the requested number, subject to validation |
| Required relationship cannot be resolved | Reject/defer the transaction without partially inserting the graph |

The same-UUID rule applies to the parent and its child records. If an incoming Android payload has the same parent UUID as a Windows record, Windows' complete parent graph is canonical. Android must not replace Windows child items merely because their item UUIDs differ or the Android parent is pending.

### Consequence of Windows authority

An Android edit to an already-existing Windows UUID is not an update to canonical data. The server returns the Windows version. If the product later needs Android editing of existing records, that requires an explicitly approved edit-request/workflow; it must not be smuggled into last-write-wins sync.

New Android-created UUIDs are accepted as new records. Once accepted, the resulting record is canonical on Windows.

## 4. Number allocation policy

### 4.1 Numbered namespaces

The initial namespaces identified by the Phase 1 audit are:

| Entity | Number field | Example |
|---|---|---|
| Order | `order_number` | `ORD-000039` |
| Invoice | `invoice_number` | `INV-000032` |
| Bill | `bill_number` | `BILL-000012` |
| Asset | `asset_code` | Existing asset-code format |

Other syncable entities without a user-facing number use UUID identity and do not invoke number allocation.

Each entity type has an independent namespace. An order number and invoice number may share the same textual value without colliding with one another.

### 4.2 Collision rule

If Windows already owns the requested number and a different UUID arrives:

- Windows keeps the existing record's number unchanged.
- The incoming distinct record is preserved.
- The incoming record receives the first available alphabetic suffix in that number's suffix family.
- The canonical number is persisted on Windows and returned in the response.
- Android stores that exact returned number.

Example:

| Record | Canonical number |
|---|---|
| Existing Windows order | `ORD-000039` |
| First distinct incoming order requesting `ORD-000039` | `ORD-000039A` |
| Next distinct incoming order requesting `ORD-000039` | `ORD-000039B` |
| Next | `ORD-000039C` |

The same rule applies to invoice and bill numbers. For example, a colliding bill becomes `BILL-000012A` on both devices.

The current schema also enforces one invoice and one bill per linked order. A different UUID attempting to create a second invoice or bill for an order is therefore rejected explicitly; it is not a number collision and must not replace or delete the existing financial graph. Number suffixing applies when distinct financial records belong to different orders (or a bill has no linked order) but request the same invoice/bill number.

### 4.3 Suffix sequence and sorting

- Suffixes use uppercase alphabetic sequence: A through Z, then AA, AB, and onward.
- Existing suffixes are considered occupied; allocation must never overwrite or duplicate one.
- If a requested suffixed value itself collides, allocation searches the corresponding root number's suffix family for the first available suffix.
- A number without a suffix sorts before its suffixed variants.
- Suffix variants sort before the next numeric base number: `ORD-000039`, `ORD-000039A`, `ORD-000039B`, `ORD-000040`.
- Parsing and formatting must preserve the established prefix and zero-padding conventions. Parsing is based on the final numeric component, so timestamp-style bill numbers retain their full existing timestamp and receive any suffix at the end (for example, `BILL-20261113-103011000042A`).

### 4.4 Allocation order and concurrency

Allocation must occur inside the same database transaction that inserts the incoming record. Concurrent requests must not receive the same suffix. The transaction must re-check uniqueness before commit.

The first successfully committed distinct UUID receives the first free suffix. Later distinct UUIDs receive subsequent suffixes. This is a server-serialized allocation policy, not an arrival-independent reordering of already accepted records.

### 4.5 Idempotency

The server checks UUID identity before allocating a number. If the UUID already exists, it returns the stored canonical record and does not allocate a new suffix—even if the retried request still contains the original unsuffixed number.

## 5. Canonical response contract

A successful push must provide enough information for the client to converge to the Windows record. A boolean-only acknowledgement is insufficient for numbered records.

The logical response should include:

- outcome: created, already-present/canonicalized, or rejected;
- entity type and UUID;
- complete canonical entity payload, including canonical number;
- canonical child records where the entity is a graph;
- resolved relationship UUIDs;
- optional conflict metadata explaining that Windows retained an existing version or allocated a suffix;
- server revision/version metadata if introduced by the implementation.

The exact JSON envelope and protocol-version strategy will be specified after reviewing the current client decoding and API compatibility requirements. Existing routes should be retained where practical. The server must enforce the policy even when receiving a legacy-shaped request.

A client must apply the returned canonical record rather than independently guessing the assigned number. It should mark the local record synced only after the canonical response has been successfully applied.

## 6. Relationship and graph rules

- Cross-device references use UUIDs, never SQLite integer IDs.
- Parent records are reconciled before dependent records.
- Orders and their order items are treated as one logical graph.
- Invoices and invoice items are treated as one logical graph.
- Bills and bill items are treated as one logical graph.
- Customers and assets must exist or be resolved before dependent records are committed.
- Inventory activities, staff attendance and staff payments must resolve their referenced UUIDs before commit.
- Salary expense and staff payment links must remain consistent.
- A number collision must never delete a different UUID's parent or children.
- If a parent with the same UUID exists on Windows, its Windows child graph remains authoritative.

## 7. Deletion and tombstone policy — approved

The Phase 1 audit found tombstone support for expenses, assets and maintenance, but not a consistent deletion workflow for all entities. The following policy is approved and applies universally to syncable entities.

1. **Windows deletion:** A deletion performed on Windows creates the authoritative tombstone for that entity UUID.
2. **Propagation:** The Windows tombstone is propagated to Android and all other peers. A tombstoned UUID must not be recreated by a stale copy or an ordinary upsert.
3. **Android deletion:** A deletion initiated on Android is a deletion request, not an immediate canonical deletion. Android records and submits the request without treating the entity as canonically deleted.
4. **Windows decision:** Windows validates the request and either accepts or rejects it. Only Windows can create the authoritative tombstone. A rejection must be returned explicitly so the client can show the outcome; it must not silently mark the entity deleted.
5. **Idempotency and retention:** Repeated deletion requests and repeated tombstone delivery are idempotent. A tombstone may be compacted only when the protocol can prove every required peer has received it, or an equivalent durable mechanism guarantees that stale copies cannot resurrect the UUID.
6. **Relationships:** Parent deletion must respect dependent records and explicit cascade/retention rules. The implementation must not silently discard dependent financial or historical records.
7. **Recovery:** A normal sync, retry, restore, or stale offline upload must not resurrect a tombstoned UUID. Any future undelete operation requires an explicit Windows-authorized workflow; it is not an ordinary Android upsert.

The server-side SyncEngine owns validation and tombstone decisions. Android submits requests and applies the canonical response.

## 8. Failure, retry and offline behaviour

- Offline-created records remain pending locally.
- On reconnect, the client submits pending records in dependency order.
- A successful server response includes the canonical record; the client applies it transactionally.
- A transport failure does not mark the record synced.
- A server rejection remains visible as a failed/pending operation and must not be converted into success.
- Retrying the same UUID is safe and returns the same canonical result.
- Partial graph failures roll back the graph transaction.
- Pull operations apply Windows canonical data even if the Android copy is locally marked pending; the pending flag must not override Windows authority.
- The normal sync path must not clear and rebuild the entire local database. Destructive pull-and-replace remains a separate explicit operation.

## 9. Entity policy matrix

| Entity | Identity | Number collision | Relationships / special key |
|---|---|---|---|
| Customers | UUID | N/A | Parent of orders, invoices, bills |
| Orders | UUID | Suffix `order_number` | Customer, order items, invoice, bill, inventory activity |
| Order items | UUID | N/A | Child of order; Windows graph wins with same parent UUID |
| Invoices | UUID | Suffix `invoice_number` | One per order; customer/order; invoice items |
| Invoice items | UUID | N/A | Child of invoice |
| Bills | UUID | Suffix `bill_number` | One per order where linked; customer/order; bill items |
| Bill items | UUID | N/A | Child of bill |
| Expenses | UUID | N/A | Optional staff payment UUID; tombstones |
| Assets | UUID | Suffix/canonical `asset_code` | Parent of maintenance; tombstones |
| Maintenance | UUID | N/A | Asset UUID; tombstones |
| Consumables | UUID | N/A | Parent of spools and inventory activity |
| Thread spools | UUID | N/A | Consumable UUID |
| Inventory activities | UUID | N/A | Consumable, optional spool/order UUID |
| Staff | UUID | N/A | Parent of attendance and payments |
| Staff attendance | UUID plus natural-key validation | N/A | Unique staff UUID + date |
| Staff payments | UUID | N/A | Staff UUID; linked salary expense |

For natural-key collisions such as staff attendance on the same staff/date, Windows' existing record is canonical. A different UUID must not be used to bypass the natural-key uniqueness constraint.

## 10. Test contract derived from these rules

The following behaviours must be tests before the corresponding implementation is considered complete:

### Identity and authority
- Same UUID with conflicting fields: Windows value wins.
- Same UUID with conflicting child item UUIDs: Windows graph wins.
- New UUID with no collision: inserted.
- New UUID with number collision: both records remain; incoming gets suffix.
- Android pending state cannot block canonical Windows pull.

### Number allocator
- Base collision allocates A.
- Repeated distinct collisions allocate B, C, and so on.
- Z rolls over to AA; AA continues to AB.
- Preoccupied suffixes are skipped.
- Collision on an already suffixed request uses the same suffix family.
- Separate entity namespaces do not collide.
- Existing Windows number never changes.
- Concurrent allocation cannot duplicate a suffix.
- Retry of an already accepted UUID does not allocate again.
- Natural ordering places suffixes between the base and next numeric number.

### Graph and relationships
- Order collision preserves both complete order graphs.
- Invoice/bill collisions preserve both complete graphs.
- UUID references resolve correctly across different local integer IDs.
- A failed child write rolls back its parent transaction.
- Staff payment and salary expense remain linked.

### Deletion and recovery
- Tombstone prevents stale resurrection.
- Tombstone propagation is idempotent.
- A failed request remains pending.
- Retried requests converge to the same canonical result.
- Offline-created records are preserved until server acceptance.

## 11. Approval and implementation sequence

The Windows-authoritative policy, universal canonical suffix numbering, and deletion-request/tombstone policy in this document have been approved.

Phase 3 added a pure number allocator with focused unit tests. Phase 4 added `SyncEngine`, a pure Windows-authoritative decision core. Phase 5 wired it into transactional Windows order persistence and canonical order responses. The next integration extends the same transaction/UUID-first policy to invoices and bills: Windows returns complete canonical financial graphs, assigns suffixes for distinct-UUID number collisions, and the client applies those canonical responses. The legacy bill timestamp-priority replacement policy has been removed; a different UUID cannot delete or replace a bill already linked to the same order. The schema's one-invoice/one-bill-per-order natural keys are explicit rejection conditions, while invoice/bill number collisions across distinct orders are suffix-resolved. Focused HTTP tests cover same-UUID authority, A/B suffix allocation, timestamp-style bill suffixes, retries, concurrency, and preservation of child items. Local Flutter execution is still required. Assets, other entity adapters, and the full tombstone protocol remain future integration work. No database migration was required.
