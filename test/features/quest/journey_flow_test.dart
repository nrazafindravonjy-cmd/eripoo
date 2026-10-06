// End-to-end journey through the real screens and the real content pack,
// offline: welcome → diagnostic → project → first quest → real-world
// mission → next quest unlocked, then a restart that keeps everything.
// Phase 3 exit criterion (DEVELOPMENT_PLAN): "parcours de bout en bout
// hors ligne". All answers are fictitious.
import 'dart:io';

import 'package:eripoo/app/app.dart';
import 'package:eripoo/app/di/core_providers.dart';
import 'package:eripoo/content/progress_state.dart';
import 'package:eripoo/core/i18n/app_language.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/diagnostic/data/facts_repository.dart';
import 'package:eripoo/features/missions/data/mission_repository.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/features/quest/data/progress_repository.dart';
import 'package:eripoo/features/settings/data/settings_store.dart';
import 'package:eripoo/features/settings/presentation/app_settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/journey_overrides.dart';
import '../../helpers/memory_secure_store.dart';
import '../../helpers/test_database.dart';
import '../../helpers/test_host.dart';

/// Fails the test if anything tries to open a network connection.
class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('network used during the offline journey');
}

void main() {
  late AppDatabase db;
  setUp(() => db = memoryDatabase());
  tearDown(() => db.close());

  Future<void> launch(WidgetTester tester) async {
    setSurfaceSize(tester, phoneSize);
    final store = SettingsStore(db);
    final container = ProviderContainer(
      overrides: [
        secureKeyStoreProvider.overrideWithValue(MemorySecureKeyStore()),
        ...journeyOverrides(db: db),
        settingsStoreProvider.overrideWithValue(store),
        initialSettingsProvider.overrideWithValue(
          await tester.runAsync(store.load) ?? (throw StateError('load')),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const EripooApp()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) =>
      tap(tester, find.text(text).last);

  Future<void> next(WidgetTester tester) => tapText(tester, 'Suivant');

  Future<void> finish(WidgetTester tester) async {
    await tapText(tester, "Terminer l'étape");
  }

  Future<void> type(WidgetTester tester, String text) async {
    final field = find.byType(TextField);
    await tester.ensureVisible(field);
    await tester.enterText(field, text);
    await tester.pumpAndSettle();
  }

  Future<void> dontKnow(WidgetTester tester) async {
    await tapText(tester, "Besoin d'aide ?");
    await tapText(tester, 'Je ne sais pas');
  }

  testWidgets('offline journey from the welcome screen to the second quest', (
    tester,
  ) async {
    final previous = HttpOverrides.current;
    HttpOverrides.global = _NoNetwork();
    addTearDown(() => HttpOverrides.global = previous);

    await launch(tester);

    // ---- welcome: Malagasy preselected, French chosen
    expect(find.text("Tongasoa eto amin'ny Eripoo"), findsOneWidget);
    final group = tester.widget<RadioGroup<AppLanguage>>(
      find.byType(RadioGroup<AppLanguage>),
    );
    expect(group.groupValue, AppLanguage.mg);
    await tapText(tester, 'Français');
    expect(find.text('Bienvenue sur Eripoo'), findsOneWidget);
    await tapText(tester, 'Commencer');

    // ---- home: the diagnostic comes first; the journey is locked
    expect(find.text('Accueil'), findsWidgets);
    await tapText(tester, 'Commencer');

    // ---- diagnostic, step 1
    expect(find.text('Où en es-tu ?'), findsWidgets);
    await next(tester); // intro
    await tapText(tester, "J'ai une idée, encore floue");
    await next(tester);
    await tapText(tester, '2 à 5 heures');
    await next(tester);
    await dontKnow(tester); // sector: "I don't know" moves on
    await tapText(tester, 'Seul ou seule');
    await finish(tester);

    // ---- diagnostic, step 2: goal and project name
    await tapText(tester, 'Commencer');
    await tapText(tester, 'Un revenu en plus');
    await next(tester);
    await type(tester, 'Savon du quartier');
    await next(tester);
    await finish(tester);

    // The project exists and is named.
    expect(find.widgetWithText(AppBar, 'Savon du quartier'), findsOneWidget);
    expect(find.text('Ta prochaine étape'), findsOneWidget);
    expect(find.text('Trouver un problème qui compte'), findsOneWidget);

    // ---- quest 1, step 1 (learn): four screens
    await tapText(tester, 'Commencer');
    expect(find.text("Pourquoi partir d'un problème ?"), findsWidgets);
    // The "step finished" message of the previous step is gone.
    expect(find.byType(SnackBar), findsNothing);
    for (var i = 0; i < 3; i++) {
      await next(tester);
    }
    await finish(tester);

    // ---- quest 1, step 2 (reflect): answers, help, synthesis
    await tapText(tester, 'Commencer');
    await tapText(tester, "Besoin d'aide ?");
    await tapText(tester, 'Voir un exemple');
    expect(
      find.textContaining('perdent une heure pour acheter du savon'),
      findsOneWidget,
    );
    await type(tester, 'Les vendeuses du marché manquent de temps.');
    await next(tester);
    await type(tester, 'Les mères qui travaillent au marché.');
    await next(tester);
    await tapText(tester, 'Chaque semaine');
    await next(tester);
    // Synthesis: what was written is shown back.
    expect(
      find.text('Les vendeuses du marché manquent de temps.'),
      findsOneWidget,
    );
    await finish(tester);

    // ---- quest 1, step 3 (act): the mission must be done first
    await tapText(tester, 'Commencer');
    await next(tester);
    await tapText(tester, "Terminer l'étape");
    expect(
      find.text("Termine d'abord la mission de cette étape."),
      findsOneWidget,
    );
    await tapText(tester, 'Voir la mission');
    expect(find.text('Observer le problème en vrai'), findsOneWidget);
    await tapText(tester, "J'accepte la mission");
    await type(tester, 'Six personnes sur dix demandent du savon.');
    await tapText(tester, "J'ai terminé");
    // Back on the step, which can now be finished.
    expect(find.text('Observer le problème en vrai'), findsOneWidget);
    await finish(tester);

    // ---- quest 2 is now the next action
    expect(find.text('Comprendre tes futurs clients'), findsOneWidget);

    // ---- what was stored (encrypted database in the app)
    final results = await tester.runAsync(() async {
      final facts = await FactsRepository(db).all();
      final project = (await ProjectRepository(db).active()).single;
      final problem = await ProjectRepository(db)
          .section(project.id, 'problem');
      final progress = await ProgressRepository(db).all();
      final mission = await MissionRepository(db).get('m.observe_problem');
      return (facts, project, problem, progress, mission);
    });
    final (facts, project, problem, progress, mission) = results!;
    expect(facts['diag.entry_profile'], 'vague_idea');
    expect(facts['diag.weekly_hours'], '2_5');
    expect(facts['diag.sector'], 'unknown');
    expect(facts['diag.goal'], 'extra_income');
    expect(facts['problem.frequency'], 'weekly');
    expect(project.title, 'Savon du quartier');
    expect(
      problem!.fields['statement'],
      'Les vendeuses du marché manquent de temps.',
    );
    for (final id in [
      'diag.s01',
      'diag.s02',
      'q01.s01',
      'q01.s02',
      'q01.s03',
    ]) {
      expect(progress[id]?.status, StepStatus.completed, reason: id);
    }
    expect(mission!.status, MissionStatus.completed);

    // ---- restart: same database, the journey continues where it was
    await tester.pumpWidget(const SizedBox());
    await launch(tester);
    expect(find.widgetWithText(AppBar, 'Savon du quartier'), findsOneWidget);
    expect(find.text('Comprendre tes futurs clients'), findsOneWidget);
    expect(find.text('Bienvenue sur Eripoo'), findsNothing);
  });
}
