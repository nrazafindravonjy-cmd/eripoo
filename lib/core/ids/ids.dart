import 'package:uuid/uuid.dart';

/// Identifier generation (docs/DATA_MODEL.md §1).
abstract final class Ids {
  static const _uuid = Uuid();

  /// Fixed namespace for Eripoo name-based identifiers (randomly chosen
  /// once; never change it, or deterministic ids would change).
  static const _namespace = '5b0e3a52-7a9e-4f61-9d6c-2f8d1c4e7a10';

  /// Time-ordered random id (UUID v7) for new entities.
  static String newId() => _uuid.v7();

  /// Random id (UUID v4) for change ids, wrap ids, device ids.
  static String random() => _uuid.v4();

  /// Deterministic id (UUID v5) for entities that exist at most once per
  /// key (profile, a diagnostic fact, a project section, a step's
  /// progress). Two devices creating the same thing offline get the same
  /// id, so synchronisation treats it as one entity instead of a
  /// duplicate.
  static String forKey(String key) => _uuid.v5(_namespace, key);
}
