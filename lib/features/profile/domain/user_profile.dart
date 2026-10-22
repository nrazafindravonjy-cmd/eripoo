/// Age bracket known to the server (docs/SECURITY.md §14). Thresholds come
/// from `jurisdiction_policies` after legal validation (P6): **no age
/// value is decided in code**.
enum AgeBracket { underMinimum, minor, adult }

class UserProfile {
  const UserProfile({
    this.displayName,
    this.birthYear,
    this.ageBracket,
    this.jurisdictionCode = 'MG',
  });

  final String? displayName;

  /// Private: synchronised only inside encrypted payloads.
  final int? birthYear;
  final AgeBracket? ageBracket;
  final String jurisdictionCode;
}

class InvalidProfile implements Exception {
  const InvalidProfile();
}

abstract final class UserProfileRules {
  static const maxNameLength = 60;

  static void validate(UserProfile p) {
    final name = p.displayName;
    if (name != null && (name.trim().isEmpty || name.length > maxNameLength)) {
      throw const InvalidProfile();
    }
    final year = p.birthYear;
    if (year != null && (year < 1900 || year > 2100)) {
      throw const InvalidProfile();
    }
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(p.jurisdictionCode)) {
      throw const InvalidProfile();
    }
  }
}
