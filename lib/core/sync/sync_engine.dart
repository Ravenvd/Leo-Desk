import 'sync_number_allocator.dart';

/// Result of applying the Windows-authoritative identity and number policy.
///
/// This class makes the decision only. The caller remains responsible for
/// persisting [canonicalRecord] in the same database transaction as any
/// dependent rows and for returning it to the requesting peer.
enum SyncReconciliationOutcome {
  created,
  canonicalExisting,
  createdWithNumberSuffix,
}

class SyncReconciliationResult<T> {
  final SyncReconciliationOutcome outcome;
  final T canonicalRecord;
  final String? canonicalNumber;

  const SyncReconciliationResult({
    required this.outcome,
    required this.canonicalRecord,
    this.canonicalNumber,
  });

  bool get isNewRecord =>
      outcome == SyncReconciliationOutcome.created ||
      outcome == SyncReconciliationOutcome.createdWithNumberSuffix;

  bool get numberWasChanged =>
      outcome == SyncReconciliationOutcome.createdWithNumberSuffix;
}

/// Pure Windows-authoritative reconciliation decisions.
///
/// UUID is the sole identity key. An existing Windows record with the same
/// UUID is returned unchanged, regardless of incoming fields or sync status.
/// A different UUID is a distinct record and is preserved; for numbered
/// entities its requested number is suffixed when already occupied.
///
/// This class deliberately performs no database I/O. A server-side adapter
/// must call it while holding the transaction/uniqueness protection used to
/// persist the returned canonical record.
class SyncEngine {
  const SyncEngine();

  /// Applies UUID authority for entities without a human-readable number.
  SyncReconciliationResult<T> reconcileByUuid<T>({
    required T incomingRecord,
    required Iterable<T> existingRecords,
    required String Function(T record) uuidOf,
  }) {
    final incomingUuid = uuidOf(incomingRecord);
    if (incomingUuid.trim().isEmpty) {
      throw ArgumentError.value(incomingUuid, 'incomingUuid',
          'Record UUID must not be empty.');
    }

    for (final existing in existingRecords) {
      if (uuidOf(existing) == incomingUuid) {
        return SyncReconciliationResult<T>(
          outcome: SyncReconciliationOutcome.canonicalExisting,
          canonicalRecord: existing,
        );
      }
    }

    return SyncReconciliationResult<T>(
      outcome: SyncReconciliationOutcome.created,
      canonicalRecord: incomingRecord,
    );
  }

  /// Applies UUID authority and canonical suffix allocation to a numbered
  /// entity namespace (orders, invoices, bills, assets, etc.).
  ///
  /// The [existingRecords] iterable must contain every current record in this
  /// entity's number namespace, not a recent/paginated subset.
  SyncReconciliationResult<T> reconcileNumberedRecord<T>({
    required T incomingRecord,
    required Iterable<T> existingRecords,
    required String Function(T record) uuidOf,
    required String Function(T record) numberOf,
    required T Function(T record, String canonicalNumber)
        withCanonicalNumber,
  }) {
    final incomingUuid = uuidOf(incomingRecord);
    if (incomingUuid.trim().isEmpty) {
      throw ArgumentError.value(incomingUuid, 'incomingUuid',
          'Record UUID must not be empty.');
    }

    final records = existingRecords.toList(growable: false);

    // UUID identity takes precedence over number collisions. Never let an
    // incoming Android payload overwrite an existing Windows record.
    for (final existing in records) {
      if (uuidOf(existing) == incomingUuid) {
        return SyncReconciliationResult<T>(
          outcome: SyncReconciliationOutcome.canonicalExisting,
          canonicalRecord: existing,
          canonicalNumber: numberOf(existing),
        );
      }
    }

    final requestedNumber = numberOf(incomingRecord);
    final canonicalNumber = SyncNumberAllocator.allocate(
      requestedNumber: requestedNumber,
      existingNumbers: records.map(numberOf),
    );
    final canonicalRecord = canonicalNumber == requestedNumber
        ? incomingRecord
        : withCanonicalNumber(incomingRecord, canonicalNumber);

    return SyncReconciliationResult<T>(
      outcome: canonicalNumber == requestedNumber
          ? SyncReconciliationOutcome.created
          : SyncReconciliationOutcome.createdWithNumberSuffix,
      canonicalRecord: canonicalRecord,
      canonicalNumber: canonicalNumber,
    );
  }
}
