import 'dart:async';

import 'package:eripoo/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(bool enabled, Widget child) => MaterialApp(
  theme: EripooTheme.dark(),
  home: EripooMascotScope(
    enabled: enabled,
    child: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('hidden when the setting is off', (tester) async {
    await tester.pumpWidget(_host(false, const EripooMascot()));
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('shown, animates a finite time, hops on touch', (tester) async {
    await tester.pumpWidget(
      _host(true, const EripooMascot(mood: EripooMood.happy, hop: true)),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as ResizeImage).imageProvider, isA<AssetImage>());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(EripooMascot));
    await tester.pumpAndSettle();
  });

  testWidgets('every mood has its image', (tester) async {
    for (final mood in EripooMood.values) {
      final data = (await rootBundle.load('assets/mascot/${mood.name}.webp'))
          .lengthInBytes;
      expect(data, greaterThan(0));
    }
  });

  testWidgets('message views show the mascot instead of the icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(true, const EripooMessageView(icon: Icons.inbox, title: 'x')),
    );
    expect(find.byType(EripooMascot), findsOneWidget);
    expect(find.byIcon(Icons.inbox), findsNothing);
  });

  testWidgets('the celebration title emphasis stays readable on yellow', (
    tester,
  ) async {
    await tester.pumpWidget(_host(false, const SizedBox()));
    final context = tester.element(find.byType(Scaffold));
    unawaited(
      showEripooCelebration(
        context,
        title: 'Quête *terminée*',
        message: 'm',
        actionLabel: 'a',
      ),
    );
    await tester.pumpAndSettle();
    final rich = tester.widget<Text>(
      find.descendant(
        of: find.byType(EripooHeadline),
        matching: find.byType(Text),
      ),
    );
    final spans = (rich.textSpan! as TextSpan).children!.cast<TextSpan>();
    final sheet = Theme.of(context).extension<EripooColors>()!.brand;
    expect(spans.last.style!.color, sheet.onBase);
  });
}
