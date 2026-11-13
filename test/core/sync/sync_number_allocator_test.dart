import 'package:flutter_test/flutter_test.dart';
import 'package:leo_desk/core/sync/sync_number_allocator.dart';

void main() {
  group('SyncNumberAllocator.allocate', () {
    test('keeps an unoccupied requested number unchanged', () {
      expect(
        SyncNumberAllocator.allocate(
          requestedNumber: 'ORD-000039',
          existingNumbers: ['ORD-000038', 'ORD-000040'],
        ),
        'ORD-000039',
      );
    });

    test('assigns A to the first distinct UUID colliding with a base number',
        () {
      expect(
        SyncNumberAllocator.allocate(
          requestedNumber: 'ORD-000039',
          existingNumbers: ['ORD-000039'],
        ),
        'ORD-000039A',
      );
    });

    test('allocates sequential suffixes and skips occupied suffixes', () {
      expect(
        SyncNumberAllocator.allocate(
          requestedNumber: 'ORD-000039',
          existingNumbers: [
            'ORD-000039',
            'ORD-000039A',
            'ORD-000039B',
          ],
        ),
        'ORD-000039C',
      );
      expect(
        SyncNumberAllocator.allocate(
          requestedNumber: 'ORD-000039',
          existingNumbers: [
            'ORD-000039',
            'ORD-000039A',
            'ORD-000039C',
          ],
        ),
        'ORD-000039B',
      );
    });

    test('rolls over from Z to AA and continues to AB', () {
      final occupied = [
        'BILL-000012',
        for (var i = 1; i <= 26; i++)
          'BILL-000012${String.fromCharCode(64 + i)}',
      ];

      expect(
        SyncNumberAllocator.allocate(
          requestedNumber: 'BILL-000012',
          existingNumbers: occupied,
        ),
        'BILL-000012AA',
      );
      expect(
        SyncNumberAllocator.allocate(
          requestedNumber: 'BILL-000012',
          existingNumbers: [...occupied, 'BILL-000012AA'],
        ),
        'BILL-000012AB',
      );
    });

    test('a colliding suffixed request uses the same suffix family', () {
      expect(
        SyncNumberAllocator.allocate(
          requestedNumber: 'INV-000032B',
          existingNumbers: [
            'INV-000032',
            'INV-000032A',
            'INV-000032B',
          ],
        ),
        'INV-000032C',
      );
    });

    test('preserves timestamp-style bill numbers and zero padding', () {
      expect(
        SyncNumberAllocator.allocate(
          requestedNumber: 'BILL-20261113-103011000042',
          existingNumbers: ['BILL-20261113-103011000042'],
        ),
        'BILL-20261113-103011000042A',
      );
    });

    test('uniqueness is case-insensitive', () {
      expect(
        SyncNumberAllocator.allocate(
          requestedNumber: 'AST-0007',
          existingNumbers: ['AST-0007', 'AST-0007a'],
        ),
        'AST-0007B',
      );
    });

    test('does not treat different number families as collisions', () {
      expect(
        SyncNumberAllocator.allocate(
          requestedNumber: 'INV-000039',
          existingNumbers: ['ORD-000039', 'BILL-000039'],
        ),
        'INV-000039',
      );
    });

    test('rejects values without a trailing numeric component', () {
      expect(
        () => SyncNumberAllocator.allocate(
          requestedNumber: 'ORDER-NEW',
          existingNumbers: ['ORDER-NEW'],
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an empty requested number', () {
      expect(
        () => SyncNumberAllocator.allocate(
          requestedNumber: ' ',
          existingNumbers: const [],
        ),
        throwsArgumentError,
      );
    });
  });

  group('SyncNumberAllocator.compare', () {
    test('places suffixes between the base and next number', () {
      final numbers = [
        'ORD-000040',
        'ORD-000039B',
        'ORD-000039',
        'ORD-000039A',
      ]..sort(SyncNumberAllocator.compare);

      expect(numbers, [
        'ORD-000039',
        'ORD-000039A',
        'ORD-000039B',
        'ORD-000040',
      ]);
    });

    test('sorts multi-letter suffixes after single-letter suffixes', () {
      final numbers = [
        'ORD-000039AA',
        'ORD-000039Z',
        'ORD-000039AB',
      ]..sort(SyncNumberAllocator.compare);

      expect(numbers, [
        'ORD-000039Z',
        'ORD-000039AA',
        'ORD-000039AB',
      ]);
    });

    test('sorts timestamp-style bill numbers chronologically', () {
      final numbers = [
        'BILL-20261113-103012000001',
        'BILL-20261113-103011999999A',
        'BILL-20261113-103011999999',
      ]..sort(SyncNumberAllocator.compare);

      expect(numbers, [
        'BILL-20261113-103011999999',
        'BILL-20261113-103011999999A',
        'BILL-20261113-103012000001',
      ]);
    });
  });
}
