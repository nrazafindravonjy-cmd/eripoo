import 'dart:async';

// Screens of the journey, one behaviour at a time (the whole path is in
// journey_flow_test.dart). Real content pack, in-memory database.
import 'package:eripoo/app/app.dart';
import 'package:eripoo/app/di/core_providers.dart';
import 'package:eripoo/app/router/app_router.dart';
import 'package:eripoo/content/progress_state.dart';
import 'package:eripoo/core/i18n/app_language.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/missions/data/mission_repository.dart';
import 'package:eripoo/features/quest/application/journey_service.dart';
import 'package:eripoo/features/quest/data/progress_repository.dart';
import 'package:eripoo/features/quest/domain/answer.dart';
import 'package:eripoo/features/settings/domain/app_settings.dart';
import 'package:eripoo/features/settings/presentation/app_settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/journey_overrides.dart';
import '../../helpers/memory_secure_store.dart';
import '../../helpers/test_database.dart';
import '../../helpers/test_host.dart';

void main() {
  late AppDatabase db;
  late JourneyService journey;
  setUp(() {
    db = memoryDatabase();
    journey = JourneyService(pack: basePack(), db: db);
  });
  tearDown(() => db.close());

  Future<void> diagnosticDone(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (final (block, value) in [
        ('stage', 'vague_idea'),
        ('hours', '2_5'),
        ('sector', 'food'),
        ('team', 'alone'),
      ]) {
        await journey.saveAnswer(
          'diag.s01',
          block,
          Answer(AnswerType.choice, value),
        );
      }
      await journey.complete('diag.s01');
      await journey.saveAnswer(
        'diag.s02',
        'goal',
        const Answer(AnswerType.choice, 'grow'),
      );
      await journey.saveAnswer(
        'diag.s02',
        'name',
        const Answer(AnswerType.text, 'Projet test'),
      );
      await journey.complete('diag.s02');
    });
  }

  Future<ProviderContainer> launch(
    WidgetTester tester, {
    AppLanguage language = AppLanguage.fr,
    String? at,
  }) async {
    setSurfaceSize(tester, phoneSize);
    final container = ProviderContainer(
      overrides: [
        secureKeyStoreProvider.overrideWithValue(MemorySecureKeyStore()),
        ...journeyOverrides(db: db),
        initialSettingsProvider.overrideWithValue(
          AppSettings(language: language),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const EripooApp()),
    );
    await tester.pumpAndSettle();
    if (at != null) {
      unawaited(container.read(routerProvider).push(at));
      await tester.pumpAndSettle();
    }
    return container;
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text).last;
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets("no language yet: the welcome screen, in the phone's language", (
    tester,
  ) async {
    setSurfaceSize(tester, phoneSize);
    final container = ProviderContainer(
      overrides: [
        secureKeyStoreProvider.overrideWithValue(MemorySecureKeyStore()),
        ...journeyOverrides(db: db),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const EripooApp()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Eripoo'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tapText(tester, 'Start');
    expect(container.read(appSettingsProvider).language, AppLanguage.en);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('the diagnostic cannot be set aside, a learning step can', (
    tester,
  ) async {
    await launch(tester, at: AppRoutes.step('diag.s01'));
    await tapText(tester, 'Suivant'); // to the first question
    await tapText(tester, "Besoin d'aide ?");
    expect(find.text('Je ne sais pas'), findsOneWidget);
    expect(find.text("Passer pour l'instant"), findsNothing);
    expect(find.text('Revenir plus tard'), findsNothing);
    await tester.tapAt(const Offset(10, 10)); // close the sheet
    await tester.pumpAndSettle();

    await diagnosticDone(tester);
    await tester.pumpWidget(const SizedBox());
    await launch(tester, at: AppRoutes.step('q01.s01'));
    await tapText(tester, "Besoin d'aide ?");
    expect(find.text('Je ne sais pas'), findsNothing); // no question here
    await tapText(tester, "Passer pour l'instant");
    final progress = await tester.runAsync(
      () => ProgressRepository(db).get('q01.s01'),
    );
    expect(progress!.status, StepStatus.deferred);
    // Back home: the next step is proposed, the skipped one is not lost.
    expect(find.text('Le problème que tu vois'), findsOneWidget);
  });

  testWidgets('a mission can be abandoned (confirmed) and taken up again', (
    tester,
  ) async {
    await diagnosticDone(tester);
    await launch(tester, at: AppRoutes.mission('m.observe_problem'));
    await tapText(tester, "J'accepte la mission");
    await tapText(tester, 'Abandonner la mission');
    expect(find.text('Abandonner cette mission ?'), findsOneWidget);
    await tapText(tester, 'Annuler');
    var mission = await tester.runAsync(
      () => MissionRepository(db).get('m.observe_problem'),
    );
    expect(mission!.status, MissionStatus.accepted);

    await tapText(tester, 'Abandonner la mission');
    await tapText(tester, 'Abandonner la mission'); // confirm
    mission = await tester.runAsync(
      () => MissionRepository(db).get('m.observe_problem'),
    );
    expect(mission!.status, MissionStatus.abandoned);

    await tapText(tester, 'Reprendre la mission');
    mission = await tester.runAsync(
      () => MissionRepository(db).get('m.observe_problem'),
    );
    expect(mission!.status, MissionStatus.accepted);

    // An empty reflection is refused with a message.
    await tapText(tester, "J'ai terminé");
    expect(find.text('Il manque encore une réponse.'), findsOneWidget);
  });

  testWidgets('drafts are shown with the review note', (tester) async {
    await diagnosticDone(tester);
    await launch(
      tester,
      language: AppLanguage.en,
      at: AppRoutes.step('q01.s01'),
    );
    expect(find.text('Why start from a problem?'), findsWidgets);
    expect(
      find.text(
        'Some texts are still being reviewed or shown in another language.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
