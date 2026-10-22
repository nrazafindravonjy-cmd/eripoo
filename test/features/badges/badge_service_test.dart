// Badges (CLAUDE.md §21) on the real content pack and local database:
// earned on what the user DID, never on reading alone, permanent and
// synchronised, announced once. Fictitious data only.
import 'package:eripoo/content/content_pack.dart';
import 'package:eripoo/content/content_validator.dart';
import 'package:eripoo/content/json_reader.dart';
import 'package:eripoo/content/localized_text.dart';
import 'package:eripoo/content/rules.dart';
import 'package:eripoo/core/i18n/app_language.dart';
import 'package:eripoo/core/ids/ids.dart';
import 'package:eripoo/core/logging/app_logger.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/badges/application/badge_service.dart';
import 'package:eripoo/features/hypotheses/application/research_service.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/features/quest/application/journey_service.dart';
import 'package:eripoo/features/trash/application/trash_service.dart';
import 'package:eripoo/security/crypto_service.dart';
import 'package:eripoo/security/key_manager.dart';
import 'package:eripoo/sync/engine/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_sync_server.dart';
import '../../helpers/journey_overrides.dart';
import '../../helpers/test_database.dart';

const owner = '0192f2a0-7c1e-7b3a-9c2d-1f2e3d4c5b6a';

void main() {
  final pack = basePack();
  late AppDatabase db;
  late BadgeService badges;
  late String project;

  BadgeService serviceFor(AppDatabase database) {
    final journey = JourneyService(pack: pack, db: database);
    return BadgeService(database, pack, input: journey.input);
  }

  setUp(() async {
    db = memoryDatabase();
    badges = serviceFor(db);
    project = (await ProjectRepository(db).create('Savon du quartier')).id;
  });
  tearDown(() => db.close());

  Future<Set<String>> earned() async => {
    for (final b in await badges.badges())
      if (b.earned) b.badge.id,
  };

  test('the pack declares badges that all reward an action', () {
    expect(pack.badges, isNotEmpty);
    expect(validatePack(pack).errors, isEmpty);
  });

  test('a badge on reading alone is refused by the validator', () {
    final reading = ContentPack(
      packId: pack.packId,
      version: pack.version,
      minAppVersion: pack.minAppVersion,
      blockTypes: pack.blockTypes,
      quests: pack.quests,
      missions: pack.missions,
      sections: pack.sections,
      tools: pack.tools,
      badges: [
        BadgeDefinition(
          id: 'badge.reader',
          title: const LocalizedText({AppLanguage.fr: 'Lecteur'}),
          description: const LocalizedText({AppLanguage.fr: 'A lu.'}),
          hint: const LocalizedText({AppLanguage.fr: 'Lis.'}),
          earnedWhen: Rule.read(
            JsonReader({'step': 'q01.s01', 'is': 'completed'}),
          ),
        ),
      ],
    );
    expect(
      validatePack(reading).errors,
      contains('badge.reader: a badge rewards an action, never reading alone'),
    );
  });

  test('badges are earned on what the user did', () async {
    expect(await badges.refreshAwards(), isEmpty);

    final research = ResearchService(db);
    await research.addObservation(projectId: project, description: 'File.');
    expect(await badges.refreshAwards(), ['badge.first_observation']);

    for (var i = 1; i <= 5; i++) {
      await research.addInterview(
        projectId: project,
        alias: 'Vendeuse $i',
        notes: 'Achète le dimanche.',
      );
    }
    expect(await badges.refreshAwards(), ['badge.good_listener']);
    expect(await badges.refreshAwards(), isEmpty, reason: 'stable');
  });

  test(
    'a badge is permanent: undoing the work does not take it back',
    () async {
      final note = await ResearchService(db)
          .addObservation(projectId: project, description: 'File.');
      await badges.refreshAwards();
      await TrashService(db).moveToTrash(TrashKind.observation, note.id);
      expect(await badges.refreshAwards(), isEmpty);
      expect(await earned(), contains('badge.first_observation'));
    },
  );

  test('announced once: seen badges are no longer new', () async {
    await ResearchService(db)
        .addObservation(projectId: project, description: 'File.');
    await badges.refreshAwards();
    var first = (await badges.badges()).firstWhere((b) => b.earned);
    expect(first.isNew, isTrue);
    await badges.markSeen([first.badge.id]);
    first = (await badges.badges()).firstWhere((b) => b.earned);
    expect(first.isNew, isFalse);
  });

  group('across two phones', () {
    late CryptoService crypto;
    setUpAll(() async => crypto = await CryptoService.init());

    test('a badge reaches the other phone; both earning it keep the '
        'earliest, without a conflict copy', () async {
      final server = FakeSyncServer();
      final umk = crypto.generateKey();
      final keys = DataKeys(crypto, umk);
      final b = memoryDatabase();
      addTearDown(() async {
        keys.dispose();
        umk.dispose();
        await b.close();
      });
      Future<void> sync(AppDatabase database, String device) =>
          SyncEngine(
            db: database,
            remote: server.clientFor(owner, session: device),
            crypto: crypto,
            logger: AppLogger(sinks: const []),
          ).runCycle(
            SyncSession(
              ownerId: owner,
              deviceId: device,
              recordKey: keys.records,
              umkVersion: 1,
            ),
          );
      final devA = Ids.random();
      final devB = Ids.random();

      await ResearchService(db)
          .addObservation(projectId: project, description: 'File.');
      await badges.refreshAwards();
      final projectB = (await ProjectRepository(b).create('Savon')).id;
      await ResearchService(b)
          .addObservation(projectId: projectB, description: 'Attente.');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await serviceFor(b).refreshAwards();
      await sync(db, devA);
      await sync(b, devB);
      await sync(db, devA);

      final onA = await db.select(db.badgeAwards).get();
      final onB = await b.select(b.badgeAwards).get();
      expect(onA.single.unlockedAt, onB.single.unlockedAt);
      expect(await b.select(b.conflictCopies).get(), isEmpty);
      expect(await db.select(db.conflictCopies).get(), isEmpty);
    });
  });
}
