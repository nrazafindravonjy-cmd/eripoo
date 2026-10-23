@Tags(['screenshots'])
library;

import 'package:eripoo/app/app.dart';
import 'package:eripoo/app/di/core_providers.dart';
import 'package:eripoo/core/i18n/app_language.dart';
import 'package:eripoo/features/settings/presentation/app_settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/component_sheet.dart';
import '../helpers/journey_overrides.dart';
import '../helpers/memory_secure_store.dart';
import '../helpers/real_fonts.dart';
import '../helpers/test_host.dart';

/// Renders review captures with real fonts into
/// test/screenshots/goldens/. Not a regression test.
void main() {
  setUpAll(loadRealFonts);

  for (final brightness in [Brightness.dark]) {
    testWidgets('components ${brightness.name}', (tester) async {
      setSurfaceSize(tester, const Size(360, 1760));
      await tester.pumpWidget(
        testHost(const ComponentSheet(), brightness: brightness),
      );
      await tester.pump(const Duration(seconds: 1));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/components_${brightness.name}.png'),
      );
    });
  }

  for (final (name, size, language) in [
    ('shell_phone_en', phoneSize, AppLanguage.en),
    ('shell_tablet_fr', tabletSize, AppLanguage.fr),
  ]) {
    testWidgets(name, (tester) async {
      setSurfaceSize(tester, size);
      final container = ProviderContainer(
        overrides: [
          secureKeyStoreProvider.overrideWithValue(MemorySecureKeyStore()),
          ...journeyOverrides(),
        ],
      );
      addTearDown(container.dispose);
      container.read(appSettingsProvider.notifier).setLanguage(language);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const EripooApp(),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$name.png'),
      );
    });
  }

  testWidgets('help sheet', (tester) async {
    setSurfaceSize(tester, phoneSize);
    await tester.pumpWidget(testHost(const ComponentSheet()));
    await tester.pump(const Duration(seconds: 1));
    await tester.scrollUntilVisible(
      find.text("Besoin d'aide ?"),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    // Let the scroll come to rest: a moving list ignores taps.
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text("Besoin d'aide ?"));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Je ne sais pas'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/help_sheet.png'),
    );
  });
}
