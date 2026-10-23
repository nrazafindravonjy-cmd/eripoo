// Accessibility audit of the app's screens (CLAUDE.md §27, Phase 10):
// touch targets of at least 48 dp, every target labelled for screen
// readers, text contrast, in light and dark, French and English; and no
// layout overflow with the text at 200 % on a small phone. Automated
// checks only: TalkBack on real phones stays to do (END_CHECKLIST).
import 'dart:io';

import 'package:eripoo/app/app.dart';
import 'package:eripoo/app/di/core_providers.dart';
import 'package:eripoo/app/router/app_router.dart';
import 'package:eripoo/core/i18n/app_language.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/finance/application/finance_service.dart';
import 'package:eripoo/features/hypotheses/presentation/research_providers.dart';
import 'package:eripoo/features/media/data/media_store.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/features/settings/domain/app_settings.dart';
import 'package:eripoo/features/settings/presentation/app_settings_controller.dart';
import 'package:eripoo/security/crypto_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/journey_overrides.dart';
import '../helpers/memory_secure_store.dart';
import '../helpers/test_database.dart';
import '../helpers/test_host.dart';

const routes = [
  AppRoutes.home,
  AppRoutes.quest,
  AppRoutes.project,
  AppRoutes.tools,
  AppRoutes.profile,
  AppRoutes.hypotheses,
  AppRoutes.fieldNotes,
  AppRoutes.finances,
  AppRoutes.cashPlan,
  AppRoutes.review,
  AppRoutes.canvas,
  AppRoutes.priceCalculator,
  AppRoutes.adminPreparation,
];

void main() {
  late CryptoService crypto;
  late AppDatabase db;
  late Directory tmp;

  setUpAll(() async => crypto = await CryptoService.init());
  setUp(() {
    db = memoryDatabase();
    tmp = Directory.systemTemp.createTempSync('eripoo_a11y');
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  /// A project with a little of everything, so screens are not empty.
  Future<void> someWork(WidgetTester tester) => tester.runAsync(() async {
    final id = (await ProjectRepository(db).create('Savon du quartier')).id;
    await ProjectRepository(db).saveSection(
      projectId: id,
      sectionKey: 'solution',
      fields: {'first_idea': 'Savon livré au marché'},
    );
    final f = FinanceService(db);
    await f.add(
      projectId: id,
      kind: FinanceKind.variableCost,
      label: 'Huile et soude',
      amountMga: 1200,
    );
    await f.add(
      projectId: id,
      kind: FinanceKind.fixedCost,
      label: 'Loyer',
      amountMga: 50000,
    );
    await f.savePlan(id, priceMga: 2000, volumeFirst: 20, volumeLast: 80);
  });

  Future<ProviderContainer> launch(
    WidgetTester tester, {
    required AppLanguage language,
    double textScale = 1,
  }) async {
    setSurfaceSize(tester, phoneSize);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = ProviderContainer(
      overrides: [
        secureKeyStoreProvider.overrideWithValue(MemorySecureKeyStore()),
        ...journeyOverrides(db: db),
        initialSettingsProvider.overrideWithValue(
          AppSettings(language: language),
        ),
        mediaStoreProvider.overrideWithValue(
          MediaStore(
            db: db,
            crypto: crypto,
            key: crypto.generateKey(),
            umkVersion: 1,
            dir: Directory('${tmp.path}/media')..createSync(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const EripooApp()),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> open(
    WidgetTester tester,
    ProviderContainer container,
    String route,
  ) async {
    container.read(routerProvider).go(route);
    await tester.pumpAndSettle();
    // Dismiss a tool celebration if one shows up.
    final dialog = find.byType(AlertDialog);
    if (dialog.evaluate().isNotEmpty) {
      await tester.tap(
        find.descendant(of: dialog, matching: find.byType(TextButton)).first,
      );
      await tester.pumpAndSettle();
    }
  }

  for (final language in [AppLanguage.fr, AppLanguage.en]) {
    {
      testWidgets('guidelines on every screen (${language.name})', (
        tester,
      ) async {
        await someWork(tester);
        final container = await launch(tester, language: language);
        final handle = tester.ensureSemantics();
        for (final route in routes) {
          await open(tester, container, route);
          await expectLater(
            tester,
            meetsGuideline(androidTapTargetGuideline),
            reason: route,
          );
          await expectLater(
            tester,
            meetsGuideline(labeledTapTargetGuideline),
            reason: route,
          );
          await expectLater(
            tester,
            meetsGuideline(textContrastGuideline),
            reason: route,
          );
        }
        handle.dispose();
      });
    }
  }

  testWidgets('text at 200 % on a small phone: nothing overflows', (
    tester,
  ) async {
    await someWork(tester);
    final container = await launch(
      tester,
      language: AppLanguage.fr,
      textScale: 2,
    );
    for (final route in routes) {
      await open(tester, container, route);
      expect(tester.takeException(), isNull, reason: route);
    }
  });
}
