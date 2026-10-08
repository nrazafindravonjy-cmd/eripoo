// The Tools tab through the real UI: sections, help of a locked tool, the
// celebration (and its off switch), the interview guide and the competitor
// analysis. Fictitious data only.
import 'dart:io';

import 'package:eripoo/app/app.dart';
import 'package:eripoo/app/di/core_providers.dart';
import 'package:eripoo/app/router/app_router.dart';
import 'package:eripoo/core/i18n/app_language.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/hypotheses/application/research_service.dart';
import 'package:eripoo/features/hypotheses/presentation/research_providers.dart';
import 'package:eripoo/features/media/data/media_store.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/features/quest/data/progress_repository.dart';
import 'package:eripoo/features/quest/domain/step_progress.dart';
import 'package:eripoo/features/settings/domain/app_settings.dart';
import 'package:eripoo/features/settings/presentation/app_settings_controller.dart';
import 'package:eripoo/features/tools/application/competitor_service.dart';
import 'package:eripoo/security/crypto_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/journey_overrides.dart';
import '../../helpers/memory_secure_store.dart';
import '../../helpers/test_database.dart';
import '../../helpers/test_host.dart';

void main() {
  final pack = basePack();
  late CryptoService crypto;
  late AppDatabase db;
  late Directory mediaDir;
  late String projectId;

  setUpAll(() async => crypto = await CryptoService.init());
  setUp(() {
    db = memoryDatabase();
    mediaDir = Directory.systemTemp.createTempSync('eripoo_ui_tools');
  });
  tearDown(() async {
    await db.close();
    mediaDir.deleteSync(recursive: true);
  });

  Future<ProviderContainer> launch(
    WidgetTester tester,
    String at, {
    AppSettings settings = const AppSettings(language: AppLanguage.fr),
  }) async {
    setSurfaceSize(tester, phoneSize);
    projectId = (await tester.runAsync(
      () => ProjectRepository(db).create('Savon du quartier'),
    ))!.id;
    final container = ProviderContainer(
      overrides: [
        secureKeyStoreProvider.overrideWithValue(MemorySecureKeyStore()),
        ...journeyOverrides(db: db, pack: pack),
        initialSettingsProvider.overrideWithValue(settings),
        mediaStoreProvider.overrideWithValue(
          MediaStore(
            db: db,
            crypto: crypto,
            key: crypto.generateKey(),
            umkVersion: 1,
            dir: mediaDir,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const EripooApp()),
    );
    await tester.pumpAndSettle();
    container.read(routerProvider).go(at);
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) =>
      tap(tester, find.text(text).last);

  Future<void> fill(WidgetTester tester, String label, String value) async {
    // Optional fields add a mark to their label.
    final field = find
        .ancestor(
          of: find.textContaining(label),
          matching: find.byType(TextField),
        )
        .last;
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
    await tester.pumpAndSettle();
  }

  Future<void> finishDiagnostic(WidgetTester tester) =>
      tester.runAsync(() async {
        final diag = pack.diagnostic!;
        for (final step in diag.steps) {
          await ProgressRepository(db)
              .setStatus(diag.id, step.id, StepStatus.completed);
        }
      });

  Finder toolsDot() => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.byType(Badge),
  );

  testWidgets('a new user: everything locked, each with its help and how '
      'to unlock it; no tool is left announced', (tester) async {
    await launch(tester, AppRoutes.tools);
    expect(find.widgetWithText(AppBar, 'Outils'), findsOneWidget);
    expect(find.text('Tes outils'), findsNothing);
    expect(find.text('À débloquer'), findsOneWidget);
    expect(find.text('Bientôt'), findsNothing);
    expect(find.text('Pas encore dans cette version.'), findsNothing);
    expect(toolsDot(), findsNothing);

    await tap(tester, find.text('Analyse concurrentielle'));
    expect(find.text('Comment s\'en servir'), findsWidgets);
    expect(
      find.textContaining('Un concurrent n\'est pas seulement'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Se débloque après deux rencontres, ou en commençant '
        '« Imaginer ta solution ».',
      ),
      findsWidgets,
    );
  });

  testWidgets('an unlock shows a dot, is celebrated once, then opens the '
      'tool', (tester) async {
    await launch(tester, AppRoutes.home);
    await finishDiagnostic(tester);
    await tester.pumpAndSettle();
    expect(toolsDot(), findsOneWidget);

    await tap(tester, find.text('Outils'));
    expect(find.text('Nouvel outil débloqué'), findsOneWidget);
    expect(
      find.text('Grâce à ce que tu as fait : Journal d\'observation.'),
      findsOneWidget,
    );
    await tapText(tester, 'Ouvrir');
    expect(find.text('Nouvel outil débloqué'), findsNothing);
    expect(toolsDot(), findsNothing, reason: 'seen');

    // Back in the tab: no second celebration.
    await tap(tester, find.text('Outils'));
    expect(find.text('Nouvel outil débloqué'), findsNothing);
    expect(find.text('Tes outils'), findsOneWidget);
    expect(find.text('Nouveau'), findsNothing);
  });

  testWidgets('celebrations off: the unlock is shown quietly', (tester) async {
    final container = await launch(tester, AppRoutes.profile);
    expect(find.text('Petites célébrations'), findsOneWidget);
    await tap(tester, find.text('Petites célébrations'));
    expect(container.read(appSettingsProvider).celebrations, isFalse);

    await finishDiagnostic(tester);
    container.read(routerProvider).go(AppRoutes.tools);
    await tester.pumpAndSettle();
    expect(find.text('Nouvel outil débloqué'), findsNothing);
    expect(find.text('Tes outils'), findsOneWidget);
    expect(toolsDot(), findsNothing);
  });

  testWidgets('the interview guide leads to the field notebook', (
    tester,
  ) async {
    await launch(tester, AppRoutes.interviewGuide);
    expect(find.widgetWithText(AppBar, 'Guide d\'interview'), findsOneWidget);
    for (final title in ['Avant', 'Pendant : les questions', 'À éviter']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(
      find.text(
        'Demande son accord pour parler cinq à dix minutes. '
        'N\'enregistre personne.',
      ),
      findsOneWidget,
    );
    await tapText(tester, 'Noter une rencontre');
    expect(find.widgetWithText(AppBar, 'Carnet de terrain'), findsOneWidget);
  });

  testWidgets('competitors: add, edit, refuse a bad price, delete and undo', (
    tester,
  ) async {
    await launch(tester, AppRoutes.competitors);
    expect(
      find.textContaining('Pas encore de concurrent noté'),
      findsOneWidget,
    );

    await tapText(tester, 'Ajouter un concurrent');
    await tapText(tester, 'Fait la même chose que toi');
    await fill(tester, 'Qui ou quoi (pas de nom de personne)', 'Épicerie A');
    await fill(tester, 'Prix observé en ariary', '1 500');
    await fill(tester, 'Pourquoi les gens le choisissent', 'Ouverte tard.');
    await tapText(tester, 'Enregistrer');
    expect(find.text('Épicerie A'), findsOneWidget);
    expect(find.textContaining('Prix vu'), findsOneWidget);
    expect(find.text('Ouverte tard.'), findsOneWidget);

    await tapText(tester, 'Modifier');
    await tapText(tester, 'Ce que les gens font sans acheter');
    await fill(
      tester,
      'Qui ou quoi (pas de nom de personne)',
      'Faire soi-même',
    );
    await fill(tester, 'Prix observé en ariary', '');
    await tapText(tester, 'Enregistrer');
    expect(find.text('Faire soi-même'), findsOneWidget);
    expect(find.text('Ce que les gens font sans acheter'), findsOneWidget);
    expect(find.textContaining('Prix vu'), findsNothing);

    await tapText(tester, 'Modifier');
    await tapText(tester, 'Fait la même chose que toi');
    await fill(tester, 'Prix observé en ariary', 'beaucoup');
    await tapText(tester, 'Enregistrer');
    expect(
      find.text('Vérifie le nom (80 caractères au plus) et le prix.'),
      findsOneWidget,
    );
    final stored = await tester.runAsync(
      () => CompetitorService(db).competitorsOf(projectId),
    );
    expect(
      stored!.single.kind,
      CompetitorKind.alternative,
      reason: 'unchanged',
    );
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
        .hideCurrentSnackBar();
    await tester.pumpAndSettle();

    await tapText(tester, 'Supprimer');
    expect(find.text('Faire soi-même'), findsNothing);
    await tapText(tester, 'Annuler');
    expect(find.text('Faire soi-même'), findsOneWidget);
  });

  testWidgets('the tool cards follow the work done in the project', (
    tester,
  ) async {
    await launch(tester, AppRoutes.tools);
    await finishDiagnostic(tester);
    await tester.runAsync(
      () => ResearchService(db).addObservation(
        projectId: projectId,
        description: 'File d\'attente à la fontaine.',
      ),
    );
    await tester.pumpAndSettle();
    // One celebration or two, depending on when the tab saw the changes.
    for (
      var i = 0;
      i < 2 && find.text('Plus tard').evaluate().isNotEmpty;
      i++
    ) {
      await tapText(tester, 'Plus tard');
    }
    expect(find.textContaining('débloqué'), findsNothing);
    await tap(tester, find.text('Guide d\'interview'));
    expect(find.widgetWithText(AppBar, 'Guide d\'interview'), findsOneWidget);
  });
}
