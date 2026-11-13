/// Allocates canonical suffixes for colliding human-readable sync numbers.
///
/// Windows calls this only after confirming that [requestedNumber] belongs to
/// a different UUID. The existing owner is never renamed. This class is pure:
/// callers supply the numbers already occupied in the relevant entity
/// namespace, and persistence/transactional locking remain the caller's job.
class SyncNumberAllocator {
  SyncNumberAllocator._();

  static final RegExp _numberPattern = RegExp(r'^(.*?)(\d+)([A-Z]*)$');

  /// Returns [requestedNumber] when it is free; otherwise returns the first
  /// free alphabetic suffix in that number's family (A..Z, AA..AZ, BA...).
  ///
  /// Matching is case-insensitive for uniqueness, while the returned value
  /// preserves the original prefix and numeric zero-padding.
  static String allocate({
    required String requestedNumber,
    required Iterable<String> existingNumbers,
  }) {
    final requested = requestedNumber.trim();
    if (requested.isEmpty) {
      throw ArgumentError.value(requestedNumber, 'requestedNumber',
          'Number must not be empty.');
    }

    final occupied = existingNumbers.map((value) => value.toUpperCase()).toSet();

    // A free legacy/custom identifier does not need suffix parsing. Only a
    // collision requires a structured trailing number so Windows can append
    // a deterministic alphabetic suffix.
    if (!occupied.contains(requested.toUpperCase())) {
      return requested;
    }

    final parsed = _parse(requested);
    final root = '${parsed.prefix}${parsed.digits}';
    var suffixIndex = 1;
    while (true) {
      final candidate = '$root${_suffixFor(suffixIndex)}';
      if (!occupied.contains(candidate.toUpperCase())) {
        return candidate;
      }
      suffixIndex++;
    }
  }

  /// Compares numbers in human order, placing a base before its suffixes and
  /// all suffixes before the next numeric base (for example 39, 39A, 39B, 40).
  static int compare(String left, String right) {
    final a = _tryParse(left);
    final b = _tryParse(right);

    if (a == null || b == null) {
      return left.toLowerCase().compareTo(right.toLowerCase());
    }

    final prefixComparison =
        a.prefix.toLowerCase().compareTo(b.prefix.toLowerCase());
    if (prefixComparison != 0) return prefixComparison;

    final numberComparison = BigInt.parse(a.digits).compareTo(
      BigInt.parse(b.digits),
    );
    if (numberComparison != 0) return numberComparison;

    return _suffixIndex(a.suffix).compareTo(_suffixIndex(b.suffix));
  }

  static _ParsedNumber _parse(String value) {
    final parsed = _tryParse(value);
    if (parsed == null) {
      throw FormatException(
        'Number must end in digits with an optional uppercase suffix.',
        value,
      );
    }
    return parsed;
  }

  static _ParsedNumber? _tryParse(String value) {
    final match = _numberPattern.firstMatch(value);
    if (match == null) return null;
    return _ParsedNumber(
      prefix: match.group(1)!,
      digits: match.group(2)!,
      suffix: match.group(3)!,
    );
  }

  static String _suffixFor(int index) {
    if (index < 1) {
      throw ArgumentError.value(index, 'index', 'Suffix index must be >= 1.');
    }

    var remaining = index;
    final characters = <String>[];
    while (remaining > 0) {
      remaining--;
      characters.add(String.fromCharCode(65 + (remaining % 26)));
      remaining ~/= 26;
    }
    return characters.reversed.join();
  }

  static int _suffixIndex(String suffix) {
    var value = 0;
    for (final unit in suffix.codeUnits) {
      value = value * 26 + (unit - 64);
    }
    return value;
  }
}

class _ParsedNumber {
  final String prefix;
  final String digits;
  final String suffix;

  const _ParsedNumber({
    required this.prefix,
    required this.digits,
    required this.suffix,
  });
}
