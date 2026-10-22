import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:eripoo/core/ids/ids.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/data/local/entity_types.dart';
import 'package:eripoo/data/local/sync_tracker.dart';
import 'package:eripoo/features/diagnostic/data/facts_repository.dart';
import 'package:eripoo/features/profile/data/profile_repository.dart';
import 'package:eripoo/features/profile/domain/user_profile.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/features/project/domain/project.dart';
import 'package:eripoo/features/quest/data/progress_repository.dart';
import 'package:eripoo/features/quest/domain/step_progress.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late TestClock clock;

  setUp(() {
    db = memoryDatabase();
    clock = TestClock();
  });
  tearDown(() => db.close());

  Future<SyncMetaRow?> meta(String type, String id) =>
      (db.select(db.syncMetaEntries)
            ..where((t) => t.entityType.equals(type) & t.entityId.equals(id)))
          .getSingleOrNull();

  group('sync marking', () {
    test('every write is marked with a new change id', () async {
      final projects = ProjectRepository(db, clock: clock.call);
      final p = await projects.create('Épicerie de quartier');
      final first = (await meta(EntityTypes.project, p.id))!.changeId;
      expect(first, isNotNull);

      await projects.rename(p.id, 'Épicerie du marché');
      final second = (await meta(EntityTypes.project, p.id))!.changeId;
      expect(second, isNot(first));
    });

    test('a failed transaction leaves neither the row nor the mark', () async {
      final tracker = SyncTracker(db);
      await expectLater(
        db.transaction(() async {
          await db
              .into(db.projects)
              .insert(
                ProjectsCompanion.insert(
                  id: 'p1',
                  title: 't',
                  maturityStage: 'exploration',
                  createdAt: 0,
                  updatedAt: 0,
                ),
              );
          await tracker.markChanged(EntityTypes.project, 'p1');
          throw StateError('crash in the middle');
        }),
        throwsStateError,
      );
      expect(await db.select(db.projects).get(), isEmpty);
      expect(await db.select(db.syncMetaEntries).get(), isEmpty);
    });

    test('an update of an unknown entity marks nothing', () async {
      final projects = ProjectRepository(db, clock: clock.call);
      await expectLater(projects.rename('missing', 'x'), throwsStateError);
      expect(await db.select(db.syncMetaEntries).get(), isEmpty);
    });

    test('pending count follows writes', () async {
      final tracker = SyncTracker(db);
      final counts = <int>[];
      final sub = tracker.watchPendingCount().listen(counts.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      await ProjectRepository(db, clock: clock.call).create('A');
      await pumpEventQueue();
      expect(counts.first, 0);
      expect(counts.last, 1);
    });
  });

  group('projects', () {
    test('created in exploration, titles are validated', () async {
      final projects = ProjectRepository(db, clock: clock.call);
      final p = await projects.create('  Atelier couture  ');
      expect(p.title, 'Atelier couture');
      expect(p.maturityStage, MaturityStage.exploration);
      await expectLater(
        projects.create('   '),
        throwsA(isA<InvalidProjectTitle>()),
      );
      await expectLater(
        projects.create('x' * 121),
        throwsA(isA<InvalidProjectTitle>()),
      );
    });

    test('trash keeps the content and can be undone', () async {
      final projects = ProjectRepository(db, clock: clock.call);
      final p = await projects.create('Jus de fruits');
      await projects.moveToTrash(p.id);
      expect(await projects.watchActive().first, isEmpty);
      expect((await projects.get(p.id))!.title, 'Jus de fruits');

      await projects.restore(p.id);
      expect((await projects.watchActive().first).single.id, p.id);
    });
  });

  group('sections and history', () {
    test('one deterministic id per project section', () async {
      final projects = ProjectRepository(db, clock: clock.call);
      final p = await projects.create('Projet');
      await projects.saveSection(
        projectId: p.id,
        sectionKey: 'problem',
        fields: {'statement': 'a'},
      );
      await projects.saveSection(
        projectId: p.id,
        sectionKey: 'problem',
        fields: {'statement': 'b'},
      );
      final rows = await db.select(db.projectSections).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, Ids.forKey('section:${p.id}:problem'));
      expect(
        (await projects.section(p.id, 'problem'))!.fields['statement'],
        'b',
      );
    });

    test('only changes of tracked fields are recorded', () async {
      final projects = ProjectRepository(db, clock: clock.call);
      final p = await projects.create('Projet');
      Future<void> save(Map<String, Object?> fields) => projects.saveSection(
        projectId: p.id,
        sectionKey: 'vision',
        fields: fields,
        trackedFields: {'statement'},
      );

      await save({'statement': 'Je veux aider les commerçants.', 'note': 'x'});
      clock.advance(const Duration(days: 3));
      await save({
        'statement': 'Je veux aider les petites épiceries.',
        'note': 'y',
      });
      await save({
        'statement': 'Je veux aider les petites épiceries.',
        'note': 'z',
      });

      final history = await projects.history(p.id);
      expect(history, hasLength(2));
      expect(history.last.previousValue, 'Je veux aider les commerçants.');
      expect(history.last.newValue, 'Je veux aider les petites épiceries.');
      final revisions = await (db.select(
        db.syncMetaEntries,
      )..where((t) => t.entityType.equals(EntityTypes.projectRevision))).get();
      expect(revisions, hasLength(2));
    });
  });

  group('profile', () {
    test('same deterministic id on every device', () async {
      final other = memoryDatabase();
      addTearDown(other.close);
      await ProfileRepository(db).save(const UserProfile(displayName: 'Hery'));
      await ProfileRepository(other)
          .save(const UserProfile(displayName: 'Hery'));
      expect(
        (await db.select(db.userProfiles).getSingle()).id,
        (await other.select(other.userProfiles).getSingle()).id,
      );
    });

    test('round-trip and validation', () async {
      final repo = ProfileRepository(db);
      await repo.save(
        const UserProfile(
          displayName: 'Hery',
          birthYear: 2008,
          ageBracket: AgeBracket.minor,
        ),
      );
      final p = await repo.load();
      expect(p.displayName, 'Hery');
      expect(p.ageBracket, AgeBracket.minor);
      await expectLater(
        repo.save(const UserProfile(displayName: ' ')),
        throwsA(isA<InvalidProfile>()),
      );
      await expectLater(
        repo.save(const UserProfile(birthYear: 1500)),
        throwsA(isA<InvalidProfile>()),
      );
    });
  });

  group('facts', () {
    test('typed values only, never free text', () async {
      final facts = FactsRepository(db);
      await facts.set('diag.idea_stage', 'vague_idea', FactSource.diagnostic);
      await facts.set('diag.weekly_hours', 5, FactSource.diagnostic);
      await facts.set('diag.has_customers', false, FactSource.diagnostic);
      expect(await facts.all(), {
        'diag.idea_stage': 'vague_idea',
        'diag.weekly_hours': 5,
        'diag.has_customers': false,
      });
      expect(
        () => facts.set('diag.idea', 'Je veux vendre du riz', FactSource.user),
        throwsArgumentError,
      );
      expect(
        () => facts.set('Bad Key', 1, FactSource.user),
        throwsArgumentError,
      );
    });
  });

  group('progress', () {
    test('start and completion dates are kept', () async {
      final progress = ProgressRepository(db, clock: clock.call);
      await progress.setStatus('q01', 'q01.s01', StepStatus.inProgress);
      final started = (await progress.get('q01.s01'))!.startedAt;
      clock.advance(const Duration(hours: 1));
      await progress.setStatus('q01', 'q01.s01', StepStatus.completed);
      final done = (await progress.get('q01.s01'))!;
      expect(done.startedAt, started);
      expect(done.completedAt, clock.now);
    });

    test('status ranks used for merging', () {
      expect(StepStatus.completed.rank, greaterThan(StepStatus.deferred.rank));
      expect(StepStatus.deferred.rank, StepStatus.inProgress.rank);
      expect(StepStatus.fastTracked.rank, StepStatus.completed.rank);
    });
  });
}
