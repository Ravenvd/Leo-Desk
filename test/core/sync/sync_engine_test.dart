import 'package:flutter_test/flutter_test.dart';
import 'package:leo_desk/core/sync/sync_engine.dart';

class _Record {
  final String uuid;
  final String number;
  final String value;

  const _Record({
    required this.uuid,
    required this.number,
    required this.value,
  });

  _Record withNumber(String value) =>
      _Record(uuid: uuid, number: value, value: this.value);
}

void main() {
  const engine = SyncEngine();

  group('SyncEngine.reconcileByUuid', () {
    test('returns the existing Windows record for the same UUID', () {
      const windows = _Record(
        uuid: 'same-id',
        number: '',
        value: 'Windows value',
      );
      const android = _Record(
        uuid: 'same-id',
        number: '',
        value: 'Android edit',
      );

      final result = engine.reconcileByUuid(
        incomingRecord: android,
        existingRecords: [windows],
        uuidOf: (record) => record.uuid,
      );

      expect(result.outcome, SyncReconciliationOutcome.canonicalExisting);
      expect(result.canonicalRecord, same(windows));
      expect(result.canonicalRecord.value, 'Windows value');
      expect(result.isNewRecord, isFalse);
    });

    test('preserves a new UUID as a distinct record', () {
      const incoming = _Record(
        uuid: 'new-id',
        number: '',
        value: 'New record',
      );

      final result = engine.reconcileByUuid(
        incomingRecord: incoming,
        existingRecords: const [
          _Record(uuid: 'other-id', number: '', value: 'Existing'),
        ],
        uuidOf: (record) => record.uuid,
      );

      expect(result.outcome, SyncReconciliationOutcome.created);
      expect(result.canonicalRecord, same(incoming));
      expect(result.isNewRecord, isTrue);
    });

    test('rejects a blank UUID', () {
      expect(
        () => engine.reconcileByUuid(
          incomingRecord: const _Record(
            uuid: ' ',
            number: '',
            value: 'Invalid',
          ),
          existingRecords: const [],
          uuidOf: (record) => record.uuid,
        ),
        throwsArgumentError,
      );
    });
  });

  group('SyncEngine.reconcileNumberedRecord', () {
    test('same UUID returns the complete Windows record before number checks',
        () {
      const windows = _Record(
        uuid: 'same-id',
        number: 'ORD-000039',
        value: 'Canonical Windows data',
      );
      const android = _Record(
        uuid: 'same-id',
        number: 'ORD-000039A',
        value: 'Conflicting Android data',
      );

      final result = engine.reconcileNumberedRecord(
        incomingRecord: android,
        existingRecords: [windows],
        uuidOf: (record) => record.uuid,
        numberOf: (record) => record.number,
        withCanonicalNumber: (record, number) => record.withNumber(number),
      );

      expect(result.outcome, SyncReconciliationOutcome.canonicalExisting);
      expect(result.canonicalRecord, same(windows));
      expect(result.canonicalNumber, 'ORD-000039');
      expect(result.canonicalRecord.value, 'Canonical Windows data');
    });

    test('new UUID with free number keeps the requested number', () {
      const incoming = _Record(
        uuid: 'new-id',
        number: 'ORD-000040',
        value: 'New order',
      );

      final result = engine.reconcileNumberedRecord(
        incomingRecord: incoming,
        existingRecords: const [
          _Record(uuid: 'existing-id', number: 'ORD-000039', value: 'Existing'),
        ],
        uuidOf: (record) => record.uuid,
        numberOf: (record) => record.number,
        withCanonicalNumber: (record, number) => record.withNumber(number),
      );

      expect(result.outcome, SyncReconciliationOutcome.created);
      expect(result.canonicalRecord.number, 'ORD-000040');
      expect(result.numberWasChanged, isFalse);
    });

    test('new UUID colliding with Windows number gets suffix A', () {
      const incoming = _Record(
        uuid: 'android-id',
        number: 'ORD-000039',
        value: 'Offline order',
      );

      final result = engine.reconcileNumberedRecord(
        incomingRecord: incoming,
        existingRecords: const [
          _Record(uuid: 'windows-id', number: 'ORD-000039', value: 'Windows'),
        ],
        uuidOf: (record) => record.uuid,
        numberOf: (record) => record.number,
        withCanonicalNumber: (record, number) => record.withNumber(number),
      );

      expect(result.outcome, SyncReconciliationOutcome.createdWithNumberSuffix);
      expect(result.canonicalRecord.uuid, 'android-id');
      expect(result.canonicalRecord.number, 'ORD-000039A');
      expect(result.canonicalNumber, 'ORD-000039A');
      expect(result.numberWasChanged, isTrue);
    });

    test('preserves all distinct UUIDs and assigns successive suffixes', () {
      const existing = [
        _Record(uuid: 'windows-id', number: 'BILL-000012', value: 'Windows'),
        _Record(uuid: 'android-one', number: 'BILL-000012A', value: 'One'),
      ];
      const incoming = _Record(
        uuid: 'android-two',
        number: 'BILL-000012',
        value: 'Two',
      );

      final result = engine.reconcileNumberedRecord(
        incomingRecord: incoming,
        existingRecords: existing,
        uuidOf: (record) => record.uuid,
        numberOf: (record) => record.number,
        withCanonicalNumber: (record, number) => record.withNumber(number),
      );

      expect(result.canonicalRecord.number, 'BILL-000012B');
      expect(result.canonicalRecord.uuid, 'android-two');
    });

    test('separate calls can reconcile independent number namespaces', () {
      const incoming = _Record(
        uuid: 'invoice-id',
        number: 'INV-000039',
        value: 'Invoice',
      );

      final result = engine.reconcileNumberedRecord(
        incomingRecord: incoming,
        existingRecords: const [
          _Record(uuid: 'order-id', number: 'ORD-000039', value: 'Order'),
        ],
        uuidOf: (record) => record.uuid,
        numberOf: (record) => record.number,
        withCanonicalNumber: (record, number) => record.withNumber(number),
      );

      expect(result.canonicalRecord.number, 'INV-000039');
    });

    test('rejects a blank UUID', () {
      expect(
        () => engine.reconcileNumberedRecord(
          incomingRecord: const _Record(
            uuid: '',
            number: 'ORD-000001',
            value: 'Invalid',
          ),
          existingRecords: const [],
          uuidOf: (record) => record.uuid,
          numberOf: (record) => record.number,
          withCanonicalNumber: (record, number) => record.withNumber(number),
        ),
        throwsArgumentError,
      );
    });
  });
}
