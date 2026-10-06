import 'package:drift/drift.dart';

import '../../../core/ids/ids.dart';
import '../../../core/time/clock.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/entity_types.dart';
import '../../../data/local/sync_tracker.dart';
import '../domain/user_profile.dart';

/// The single user profile (deterministic id: the same on every device of
/// an account, so it never duplicates).
class ProfileRepository {
  ProfileRepository(this._db, {this._clock = systemClock})
    : _sync = SyncTracker(_db);

  final AppDatabase _db;
  final Clock _clock;
  final SyncTracker _sync;

  static final profileId = Ids.forKey('profile');

  Future<UserProfile> load() async {
    final row = await (_db.select(
      _db.userProfiles,
    )..where((t) => t.id.equals(profileId))).getSingleOrNull();
    if (row == null) return const UserProfile();
    return UserProfile(
      displayName: row.displayName,
      birthYear: row.birthYear,
      ageBracket: row.ageBracket == null
          ? null
          : AgeBracket.values.byName(row.ageBracket!),
      jurisdictionCode: row.jurisdictionCode,
    );
  }

  Future<void> save(UserProfile profile) async {
    UserProfileRules.validate(profile);
    final now = _clock().millisecondsSinceEpoch;
    await _db.transaction(() async {
      final existing = await (_db.select(
        _db.userProfiles,
      )..where((t) => t.id.equals(profileId))).getSingleOrNull();
      await _db
          .into(_db.userProfiles)
          .insertOnConflictUpdate(
            UserProfilesCompanion.insert(
              id: profileId,
              displayName: Value(profile.displayName),
              birthYear: Value(profile.birthYear),
              ageBracket: Value(profile.ageBracket?.name),
              jurisdictionCode: Value(profile.jurisdictionCode),
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
            ),
          );
      await _sync.markChanged(EntityTypes.profile, profileId);
    });
  }
}
