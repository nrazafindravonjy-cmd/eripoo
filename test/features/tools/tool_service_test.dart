// Progressive unlocking of the tools (CLAUDE.md §20) on the real content
// pack and local database: each tool unlocks on what the user DID, an
// unlock is permanent and synchronised, a tool not built yet is never
// usable. The competitor analysis records. Fictitious data only.
import 'package:eripoo/content/content_pack.dart';
import 'package:eripoo/content/content_validator.dart';
import 'package:eripoo/content/json_reader.dart';
import 'package:eripoo/content/localized_text.dart';
import 'package:eripoo/content/rules.dart';
import 'package:eripoo/core/ids/ids.dart';
import 'package:eripoo/core/logging/app_logger.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/hypotheses/application/research_service.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/features/quest/application/journey_service.dart';
import 'package:eripoo/features/quest/data/progress_repository.dart';
import 'package:eripoo/features/quest/domain/step_progress.dart';
import 'package:eripoo/features/tools/application/competitor_service.dart';
import 'package:eripoo/features/tools/application/tool_service.dart';
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
  late ToolService tools;
  late String project;

  ToolService serviceFor(AppDatabase database) {
    final journey = JourneyService(pack: pack, db: database);
    return ToolService(database, pack, input: journey.input);
  }

  setUp(() async {
    db = memoryDatabase();
    tools = serviceFor(db);
    project = (await ProjectRepository(db).create('Savon du quartier')).id;
  });
  tearDown(() => db.close());

  Future<void> finishDiagnostic(AppDatabase database) async {
    final diag = pack.diagnostic!;
    for (final step in diag.steps) {
      await ProgressRepository(database)
          .setStatus(diag.id, step.id, StepStatus.completed);
    }
  }

  Future<Set<String>> unlocked() async => {
    for (final t in await tools.tools())
      if (t.unlocked) t.tool.id,
  };

  test(
    'the 14 tools of the spec, in its order; the built ones can be opened',
    () {
      expect(pack.tools.map((t) => t.kind), ToolKind.values);
      expect(
        pack.tools.where((t) => t.implemented).map((t) => t.kind),
        implementedTools,
      );
      expect(validatePack(pack).errors, isEmpty);
      for (final t in pack.tools) {
        expect(t.help, isNotEmpty, reason: t.id);
        expect(t.unlockHint, isNotNull, reason: t.id);
      }
    },
  );

  test('tools unlock on what the user did, one after the other', () async {
    expect(await tools.refreshUnlocks(), isEmpty);

    await finishDiagnostic(db);
    expect(await tools.refreshUnlocks(), ['tool.observation_journal']);

    final research = ResearchService(db);
    await research.addObservation(projectId: project, description: 'File.');
    expect(await tools.refreshUnlocks(), ['tool.interview_guide']);

    await research.createHypothesis(projectId: project, statement: 'H');
    expect(await tools.refreshUnlocks(), ['tool.experiments']);

    for (final alias in ['Vendeuse A', 'Vendeuse B']) {
      await research.addInterview(
        projectId: project,
        alias: alias,
        notes: 'Achète le dimanche.',
      );
    }
    expect(await tools.refreshUnlocks(), ['tool.competitor_analysis']);

    // The price calculator (Phase 7) unlocks with a first competitor.
    await CompetitorService(db).add(
      projectId: project,
      name: 'Épicerie du coin',
      kind: CompetitorKind.direct,
    );
    expect(await tools.refreshUnlocks(), ['tool.price_calculator']);
    final price = (await tools.tools()).firstWhere(
      (t) => t.tool.id == 'tool.price_calculator',
    );
    expect(price.usable, isTrue);
    expect(price.isNew, isTrue);

    // A locked tool is never usable, even once built.
    final admin = ToolState(
      tool: pack.tool('tool.admin_preparation')!,
      unlockedAt: null,
      seen: false,
    );
    expect(admin.tool.implemented, isTrue, reason: 'Phase 8');
    expect(admin.usable, isFalse);
    expect(admin.isNew, isFalse);
    expect(await tools.refreshUnlocks(), isEmpty, reason: 'stable');
  });

  test('an unlock is permanent: undoing the work does not re-lock', () async {
    await finishDiagnostic(db);
    final note = await ResearchService(db)
        .addObservation(projectId: project, description: 'File.');
    await tools.refreshUnlocks();
    await TrashService(db).moveToTrash(TrashKind.observation, note.id);
    expect(await tools.refreshUnlocks(), isEmpty);
    expect(await unlocked(), contains('tool.interview_guide'));
  });

  test('announced once: seen tools are no longer new', () async {
    await finishDiagnostic(db);
    await tools.refreshUnlocks();
    var journal = (await tools.tools()).first;
    expect(journal.isNew, isTrue);
    await tools.markSeen([journal.tool.id]);
    journal = (await tools.tools()).first;
    expect(journal.isNew, isFalse);
  });

  group('across two phones', () {
    late CryptoService crypto;
    setUpAll(() async => crypto = await CryptoService.init());

    test('an unlock reaches the other phone; both unlocking keep the '
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

      // Both phones finish the diagnostic offline, A first.
      await finishDiagnostic(db);
      await tools.refreshUnlocks();
      await finishDiagnostic(b);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await serviceFor(b).refreshUnlocks();
      await sync(db, devA);
      await sync(b, devB);
      await sync(db, devA);

      final onA = await db.select(db.toolUnlocks).get();
      final onB = await b.select(b.toolUnlocks).get();
      expect(onA.single.unlockedAt, onB.single.unlockedAt);
      expect(await b.select(b.conflictCopies).get(), isEmpty);
      expect(await db.select(db.conflictCopies).get(), isEmpty);
    });
  });

  group('competitor analysis', () {
    test(
      'noted, edited, refused when invalid, deleted through the trash',
      () async {
        final service = CompetitorService(db);
        final c = await service.add(
          projectId: project,
          name: '  Épicerie du coin ',
          kind: CompetitorKind.direct,
          priceMga: 1500,
          strengths: 'Ouverte tard.',
        );
        expect(c.name, 'Épicerie du coin');
        final edited = await service.update(
          c.id,
          name: 'Épicerie du coin',
          kind: CompetitorKind.direct,
          priceMga: 1800,
          weaknesses: 'Loin du marché.',
        );
        expect(edited.priceMga, 1800);
        expect(edited.strengths, isNull, reason: 'cleared on purpose');

        for (final bad in [
          () => service.add(
            projectId: project,
            name: ' ',
            kind: CompetitorKind.direct,
          ),
          () => service.add(
            projectId: project,
            name: 'X',
            kind: CompetitorKind.direct,
            priceMga: -1,
          ),
          () => service.add(
            projectId: project,
            name: 'X' * 81,
            kind: CompetitorKind.direct,
          ),
        ]) {
          await expectLater(bad(), throwsA(isA<InvalidCompetitor>()));
        }

        await TrashService(db).moveToTrash(TrashKind.competitor, c.id);
        expect(await service.competitorsOf(project), isEmpty);
        expect(
          (await TrashService(db).items()).single.label,
          'Épicerie du coin',
        );
      },
    );
  });

  group('content validation of tools', () {
    ToolDefinition tool(
      String id,
      ToolKind kind, {
      Rule? unlock,
      bool hint = true,
    }) => ToolDefinition(
      id: id,
      kind: kind,
      title: LocalizedText.read(JsonReader({'fr': 'Outil'})),
      summary: LocalizedText.read(JsonReader({'fr': 'Résumé'})),
      help: [
        LocalizedText.read(JsonReader({'fr': 'Aide'})),
      ],
      unlock: unlock,
      unlockHint: hint
          ? LocalizedText.read(JsonReader({'fr': 'Indice'}))
          : null,
    );
    ContentPack withTools(List<ToolDefinition> list) => ContentPack(
      packId: pack.packId,
      version: pack.version,
      minAppVersion: pack.minAppVersion,
      blockTypes: pack.blockTypes,
      quests: pack.quests,
      missions: pack.missions,
      sections: pack.sections,
      tools: list,
    );
    Rule rule(Map<String, Object?> json) => Rule.read(JsonReader(json));

    test('duplicates, missing hints and unknown references are refused', () {
      final errors = validatePack(
        withTools([
          tool('t.a', ToolKind.hypotheses),
          tool('t.a', ToolKind.hypotheses),
          tool(
            't.b',
            ToolKind.pitch,
            unlock: rule({'quest': 'q99', 'is': 'completed'}),
          ),
          tool(
            't.c',
            ToolKind.pitchDeck,
            unlock: rule({'count': 'interviews', 'gte': 1}),
            hint: false,
          ),
        ]),
      ).errors.join('\n');
      expect(errors, contains('duplicate tool id'));
      expect(errors, contains('declared twice'));
      expect(errors, contains('unknown quest q99'));
      expect(errors, contains('needs an unlock_hint'));
    });
  });
}
