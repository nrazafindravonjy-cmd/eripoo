/// Recovery code format (docs/SECURITY.md §5.2): 35 random digits followed
/// by one Damm check digit, displayed as 9 groups of 4.
///
/// The Damm digit only detects typing mistakes (every single-digit error
/// and every swap of two adjacent digits). It is not cryptography and it is
/// never sent to the server.
abstract final class RecoveryCode {
  static const randomDigits = 35;
  static const totalDigits = 36;
  static const groupSize = 4;

  // Damm's quasigroup of order 10 (H. Michael Damm, 2004), as published.
  static const _damm = [
    [0, 3, 1, 7, 5, 9, 8, 6, 4, 2],
    [7, 0, 9, 2, 1, 5, 4, 8, 6, 3],
    [4, 2, 0, 6, 8, 7, 1, 3, 5, 9],
    [1, 7, 5, 0, 9, 8, 3, 4, 2, 6],
    [6, 1, 2, 3, 0, 4, 5, 9, 7, 8],
    [3, 6, 7, 4, 2, 0, 9, 5, 8, 1],
    [5, 8, 6, 9, 7, 2, 0, 1, 3, 4],
    [8, 9, 4, 5, 3, 6, 2, 0, 1, 7],
    [9, 4, 3, 8, 6, 1, 7, 2, 0, 5],
    [2, 5, 8, 1, 4, 3, 6, 7, 9, 0],
  ];

  static int _dammInterim(String digits) {
    var interim = 0;
    for (final unit in digits.codeUnits) {
      interim = _damm[interim][unit - 0x30];
    }
    return interim;
  }

  /// Check digit for a string of digits.
  static int checkDigit(String digits) => _dammInterim(digits);

  /// Builds the full 36-digit code from 35 random digits (each 0–9, drawn
  /// uniformly by the caller with libsodium).
  static String fromRandomDigits(List<int> digits) {
    if (digits.length != randomDigits || digits.any((d) => d < 0 || d > 9)) {
      throw ArgumentError('Expected $randomDigits digits between 0 and 9.');
    }
    final body = digits.join();
    return '$body${checkDigit(body)}';
  }

  /// Keeps only the digits of a typed code (spaces, dashes and line breaks
  /// are ignored). Returns null if anything else was typed.
  static String? normalize(String input) {
    final compact = input.replaceAll(RegExp(r'[\s\-–.]'), '');
    if (!RegExp(r'^\d*$').hasMatch(compact)) return null;
    return compact;
  }

  /// True when [code] has 36 digits and a valid check digit.
  static bool isWellFormed(String code) =>
      code.length == totalDigits &&
      RegExp(r'^\d+$').hasMatch(code) &&
      _dammInterim(code) == 0;

  /// The 35 random digits: the only part used as key material.
  static String secretPart(String code) {
    if (!isWellFormed(code)) throw const FormatException('Invalid code');
    return code.substring(0, randomDigits);
  }

  /// `4829 1730 6654 …` for display.
  static List<String> groups(String code) => [
    for (var i = 0; i < code.length; i += groupSize)
      code.substring(i, (i + groupSize).clamp(0, code.length)),
  ];
}
