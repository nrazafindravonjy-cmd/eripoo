import 'package:eripoo/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_host.dart';

void main() {
  group('EripooButton', () {
    testWidgets('calls onPressed', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        testHost(EripooButton(label: 'Continuer', onPressed: () => taps++)),
      );
      await tester.tap(find.text('Continuer'));
      expect(taps, 1);
    });

    testWidgets('ignores presses while loading', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        testHost(
          EripooButton(
            label: 'Envoyer',
            isLoading: true,
            onPressed: () => taps++,
          ),
        ),
      );
      await tester.tap(find.text('Envoyer'), warnIfMissed: false);
      expect(taps, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('primary action is at least 56 dp high', (tester) async {
      await tester.pumpWidget(
        testHost(EripooButton(label: 'OK', onPressed: () {})),
      );
      expect(
        tester.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(EripooLayout.primaryActionHeight),
      );
    });

    testWidgets('exposes its label to screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        testHost(EripooButton(label: 'Continuer', onPressed: () {})),
      );
      expect(
        tester.getSemantics(find.byType(EripooButton)),
        matchesSemantics(
          label: 'Continuer',
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
        ),
      );
      handle.dispose();
    });
  });

  group('EripooTextField', () {
    testWidgets('marks optional fields in the current language', (
      tester,
    ) async {
      await tester.pumpWidget(
        testHost(
          const EripooTextField(label: 'Ville', isOptional: true),
          languageCode: 'en',
        ),
      );
      expect(find.text('Ville (optional)'), findsOneWidget);
    });

    testWidgets('shows the error as text', (tester) async {
      await tester.pumpWidget(
        testHost(const EripooTextField(label: 'Nom', errorText: 'Requis')),
      );
      expect(find.text('Requis'), findsOneWidget);
    });
  });

  group('EripooProgress', () {
    testWidgets('shows and announces the fraction', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        testHost(const EripooProgress(done: 4, total: 12, label: 'Quête')),
      );
      await tester.pumpAndSettle();
      expect(find.text('4 / 12'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(EripooProgress)),
        matchesSemantics(label: 'Quête', value: '4 sur 12'),
      );
      handle.dispose();
    });
  });

  testWidgets('EripooStepTrack announces the current stage', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      testHost(
        const EripooStepTrack(steps: ['A', 'B', 'C'], currentIndex: 1),
        languageCode: 'mg',
      ),
    );
    expect(
      tester.getSemantics(find.byType(EripooStepTrack)),
      matchesSemantics(label: "Dingana 2 amin'ny 3: B"),
    );
    handle.dispose();
  });

  testWidgets('EripooBadge announces earned and locked states', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      testHost(
        const Row(
          children: [
            EripooBadge(name: 'Vérité', icon: Icons.search, earned: true),
            EripooBadge(name: 'Vente', icon: Icons.store, earned: false),
          ],
        ),
      ),
    );
    expect(find.bySemanticsLabel('Badge obtenu : Vérité'), findsOneWidget);
    expect(find.bySemanticsLabel('Badge à obtenir : Vente'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    handle.dispose();
  });

  group('state views', () {
    testWidgets('error view retries', (tester) async {
      var retries = 0;
      await tester.pumpWidget(
        testHost(EripooErrorView(onRetry: () => retries++)),
      );
      expect(find.text('Un problème est survenu'), findsOneWidget);
      await tester.tap(find.text('Réessayer'));
      expect(retries, 1);
    });

    testWidgets('loading view uses the default message', (tester) async {
      await tester.pumpWidget(
        testHost(const EripooLoadingView(), languageCode: 'mg'),
      );
      expect(find.text('Andraso kely…'), findsOneWidget);
    });

    testWidgets('offline banner is calm and localized', (tester) async {
      await tester.pumpWidget(
        testHost(const EripooOfflineBanner(), languageCode: 'en'),
      );
      expect(
        find.text('Offline. Your work is saved on this phone.'),
        findsOneWidget,
      );
    });
  });

  group('EripooHelpButton', () {
    testWidgets('reports the chosen help action', (tester) async {
      HelpAction? chosen;
      await tester.pumpWidget(
        testHost(EripooHelpButton(onSelected: (a) => chosen = a)),
      );
      await tester.tap(find.text("Besoin d'aide ?"));
      await tester.pumpAndSettle();
      for (final label in [
        'Je ne sais pas',
        'Je ne comprends pas',
        'Voir un exemple',
        "M'aider",
        "Passer pour l'instant",
        'Revenir plus tard',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Voir un exemple'));
      await tester.pumpAndSettle();
      expect(chosen, HelpAction.showExample);
    });

    testWidgets('dismissing reports nothing', (tester) async {
      HelpAction? chosen;
      await tester.pumpWidget(
        testHost(
          EripooHelpButton(
            onSelected: (a) => chosen = a,
            actions: const [HelpAction.dontKnow],
          ),
        ),
      );
      await tester.tap(find.text("Besoin d'aide ?"));
      await tester.pumpAndSettle();
      expect(find.text('Voir un exemple'), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(chosen, isNull);
    });
  });

  group('showEripooConfirmDialog', () {
    Future<bool?> open(WidgetTester tester, String buttonToTap) async {
      bool? result;
      await tester.pumpWidget(
        testHost(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showEripooConfirmDialog(
                context,
                title: 'Supprimer ?',
                message: 'Tu pourras le restaurer pendant 30 jours.',
                confirmLabel: 'Supprimer',
                destructive: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(buttonToTap));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('confirm returns true', (tester) async {
      expect(await open(tester, 'Supprimer'), isTrue);
    });

    testWidgets('cancel returns false', (tester) async {
      expect(await open(tester, 'Annuler'), isFalse);
    });
  });

  group('EripooMotion', () {
    testWidgets('collapses durations when animations are disabled', (
      tester,
    ) async {
      late EripooMotion motion;
      await tester.pumpWidget(
        testHost(
          Builder(
            builder: (context) {
              motion = EripooMotion.of(context);
              return const SizedBox();
            },
          ),
          disableAnimations: true,
        ),
      );
      expect(motion.reduced, isTrue);
      expect(motion.slow, Duration.zero);
    });
  });

  test('window size classes', () {
    expect(WindowSize.fromWidth(360), WindowSize.compact);
    expect(WindowSize.fromWidth(599), WindowSize.compact);
    expect(WindowSize.fromWidth(600), WindowSize.medium);
    expect(WindowSize.fromWidth(800), WindowSize.medium);
    expect(WindowSize.fromWidth(840), WindowSize.expanded);
    expect(WindowSize.compact.gutter, EripooLayout.gutterCompact);
    expect(WindowSize.medium.gutter, EripooLayout.gutterMedium);
  });
}
