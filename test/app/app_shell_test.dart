import 'package:eripoo/app/app.dart';
import 'package:eripoo/app/di/core_providers.dart';
import 'package:eripoo/core/i18n/app_language.dart';
import 'package:eripoo/design_system/design_system.dart';
import 'package:eripoo/features/settings/domain/app_settings.dart';
import 'package:eripoo/features/settings/presentation/app_settings_controller.dart';
import 'package:eripoo/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/memory_secure_store.dart';
import '../helpers/real_fonts.dart';
import '../helpers/test_host.dart';

Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  Size size = phoneSize,
  AppSettings settings = const AppSettings(language: AppLanguage.fr),
}) async {
  setSurfaceSize(tester, size);
  final container = ProviderContainer(
    overrides: [
      secureKeyStoreProvider.overrideWithValue(MemorySecureKeyStore()),
    ],
  );
  addTearDown(container.dispose);
  final controller = container.read(appSettingsProvider.notifier)
    ..setTheme(settings.theme)
    ..setLanguage(settings.language)
    ..setReducedMotion(settings.reducedMotion);
  expect(controller.state, settings);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const EripooApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  test('supports exactly mg, fr and en', () {
    expect(
      AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet(),
      {'mg', 'fr', 'en'},
    );
  });

  testWidgets('phone: bottom navigation with the five sections', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    for (final label in ['Accueil', 'Ma quête', 'Projet', 'Outils', 'Profil']) {
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
  });

  group('with real fonts', () {
    setUpAll(loadRealFonts);

    for (final language in AppLanguage.values) {
      testWidgets('phone: ${language.name} navigation labels fit on one line', (
        tester,
      ) async {
        await pumpApp(tester, settings: AppSettings(language: language));
        // Icons are also RichText (one glyph): keep the text labels only.
        final labels = find
            .descendant(
              of: find.byType(NavigationBar),
              matching: find.byType(RichText),
            )
            .evaluate()
            .where(
              (e) =>
                  (e.renderObject! as RenderParagraph).text
                      .toPlainText()
                      .length >
                  1,
            )
            .toList();
        expect(labels, hasLength(5));
        for (final element in labels) {
          final paragraph = element.renderObject! as RenderParagraph;
          final lines = paragraph.getBoxesForSelection(
            TextSelection(
              baseOffset: 0,
              extentOffset: paragraph.text.toPlainText().length,
            ),
          );
          final tops = lines.map((box) => box.top).toSet();
          expect(tops, hasLength(1), reason: paragraph.text.toPlainText());
        }
      });
    }
  });

  testWidgets('tablet: navigation rail instead of bottom bar', (tester) async {
    await pumpApp(tester, size: tabletSize);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('landscape tablet (Android 16 may ignore portrait lock)', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(1280, 800));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching sections shows the selected one', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Projet'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Projet'), findsOneWidget);
    await tester.tap(find.text('Outils'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Outils'), findsOneWidget);
  });

  testWidgets('unbuilt sections say so honestly', (tester) async {
    await pumpApp(tester);
    expect(find.text('Pas encore disponible'), findsOneWidget);
  });

  for (final (language, home) in [
    (AppLanguage.mg, 'Fandraisana'),
    (AppLanguage.fr, 'Accueil'),
    (AppLanguage.en, 'Home'),
  ]) {
    testWidgets('renders in ${language.name}', (tester) async {
      await pumpApp(tester, settings: AppSettings(language: language));
      expect(find.widgetWithText(AppBar, home), findsOneWidget);
      final context = tester.element(find.byType(NavigationBar));
      expect(AppLocalizations.of(context).localeName, language.name);
      // Framework strings must resolve in every language (mg falls back
      // to French until Malagasy framework localizations exist).
      expect(MaterialLocalizations.of(context).okButtonLabel, isNotEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('dark theme setting applies the dark palette', (tester) async {
    await pumpApp(
      tester,
      settings: const AppSettings(
        theme: ThemePreference.dark,
        language: AppLanguage.fr,
      ),
    );
    final context = tester.element(find.byType(NavigationBar));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(context.colors.background, EripooColors.dark.background);
  });

  testWidgets('reduced motion setting disables animations', (tester) async {
    await pumpApp(
      tester,
      settings: const AppSettings(
        language: AppLanguage.fr,
        reducedMotion: true,
      ),
    );
    final context = tester.element(find.byType(NavigationBar));
    expect(EripooMotion.of(context).reduced, isTrue);
  });
}
