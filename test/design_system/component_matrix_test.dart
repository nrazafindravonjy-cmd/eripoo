import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/component_sheet.dart';
import '../helpers/test_host.dart';

/// Renders every component in light/dark × phone/tablet × fr/en, at
/// normal and doubled font size, and checks accessibility guidelines.
void main() {
  for (final variant in allVariants) {
    testWidgets('component sheet — $variant', (tester) async {
      // Real width, tall surface: every component is on screen, so the
      // guidelines check all of them (off-screen nodes are skipped).
      setSurfaceSize(tester, Size(variant.size.width, 2400));
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        testHost(
          const ComponentSheet(),
          brightness: variant.brightness,
          languageCode: variant.languageCode,
        ),
      );
      // The loading button animates forever: advance time instead of settling.
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
    });

    testWidgets('component sheet at 200 % text — $variant', (tester) async {
      setSurfaceSize(tester, variant.size);
      await tester.pumpWidget(
        testHost(
          const ComponentSheet(),
          brightness: variant.brightness,
          languageCode: variant.languageCode,
          textScale: 2,
        ),
      );
      // The loading button animates forever: advance time instead of settling.
      await tester.pump(const Duration(seconds: 1));
      // Any RenderFlex overflow would surface here as an exception.
      expect(tester.takeException(), isNull);
    });
  }
}
