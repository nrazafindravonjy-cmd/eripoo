import '../../../content/content_pack.dart';
import '../../../data/local/app_database.dart';

/// Which version of the legal texts this phone's user accepted (local
/// key/value, like the other preferences of this phone).
class LegalAcceptance {
  LegalAcceptance(this._db);

  final AppDatabase _db;

  static const _key = 'legal.accepted_version';

  /// Acceptance is asked only for validated texts, and again at each new
  /// version. Placeholders (status pending) are never offered.
  Future<bool> needed(LegalContent? legal) async {
    if (legal == null || !legal.validated) return false;
    return await _db.readValue(_key) != legal.version;
  }

  Future<void> accept(LegalContent legal) =>
      _db.writeValue(_key, legal.version);
}
