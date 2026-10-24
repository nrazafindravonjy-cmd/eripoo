// The project's numbers and the calculators through the real UI.
// Fictitious data only.
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
import 'package:eripoo/features/tools/application/competitor_service.dart';
import 'package:eripoo/security/crypto_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/activate.dart';
import '../../helpers/journey_overrides.dart';
import '../../helpers/memory_secure_store.dart';
import '../../helpers/test_database.dart';
import '../../helpers/test_host.dart';

/// The French formatter's separators.
const nnbsp = ' ';
const nbsp = ' ';
String ar(String digits) => '$digits${nbsp}Ar';

void main() {
  late CryptoService crypto;
  late AppDatabase db;
  late Directory mediaDir;
  late String projectId;

  setUpAll(() async => crypto = await CryptoService.init());
  setUp(() {
    db = memoryDatabase();
    mediaDir = Directory.systemTemp.createTempSync('eripoo_ui_finance');
  });
  tearDown(() async {
    await db.close();
    mediaDir.deleteSync(recursive: true);
  });

  Future<ProviderContainer> launch(WidgetTester tester, String at) async {
    setSurfaceSize(tester, phoneSize);
    projectId = (await tester.runAsync(
      () => ProjectRepository(db).create('Savon du quartier'),
    ))!.id;
    final container = ProviderContainer(
      overrides: [
        secureKeyStoreProvider.overrideWithValue(MemorySecureKeyStore()),
        ...journeyOverrides(db: db),
        initialSettingsProvider.overrideWithValue(
          const AppSettings(language: AppLanguage.fr),
        ),
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
    await activate(tester, finder);
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) =>
      tap(tester, find.text(text).last);

  Future<void> fill(WidgetTester tester, String label, String value) async {
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

  Future<void> soapWorkshop(WidgetTester tester) => tester.runAsync(() async {
    final f = FinanceService(db);
    await f.add(
      projectId: projectId,
      kind: FinanceKind.variableCost,
      label: 'Huile',
      amountMga: 600,
    );
    await f.add(
      projectId: projectId,
      kind: FinanceKind.fixedCost,
      label: 'Loyer',
      amountMga: 120000,
    );
    await f.add(
      projectId: projectId,
      kind: FinanceKind.investment,
      label: 'Moules',
      amountMga: 300000,
    );
  });

  testWidgets('from nothing to results: each missing input is named', (
    tester,
  ) async {
    await launch(tester, AppRoutes.project);
    await tap(tester, find.text('Mes chiffres'));
    expect(find.widgetWithText(AppBar, 'Mes chiffres'), findsOneWidget);
    expect(
      find.text(
        'Ajoute ce que coûte une unité pour que les calculs soient '
        'justes.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Choisis un prix pour voir ta marge et ton seuil de '
        'rentabilité.',
      ),
      findsOneWidget,
    );

    // A unit cost, through the form.
    await tap(tester, find.text('Ajouter').first);
    await fill(tester, 'Ce que c\'est', 'Huile');
    await fill(tester, 'Montant en ariary', '600');
    await tapText(tester, 'Enregistrer');
    expect(find.text('Huile'), findsOneWidget);
    expect(find.text('Total : ${ar('600')}'), findsOneWidget);

    // Money found: the source is asked first.
    await tap(tester, find.text('Ajouter').last);
    await tapText(tester, 'Mes économies');
    await fill(tester, 'Ce que c\'est', 'Économies');
    await fill(tester, 'Montant en ariary', '200 000');
    await tapText(tester, 'Enregistrer');
    expect(find.text('Économies'), findsOneWidget);

    // The price and the sales.
    await tapText(tester, 'Choisir le prix et les ventes');
    await fill(tester, 'Prix de vente d\'une unité', '1000');
    await fill(tester, 'Unités vendues le premier mois', '100');
    await fill(tester, 'Unités vendues le douzième mois', '400');
    await tapText(tester, 'Enregistrer');
    expect(
      find.text(
        'Sur chaque unité, il te reste ${ar('400')} (40$nbsp% du '
        'prix).',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Sans frais fixes, chaque vente te rapporte dès la '
        'première.',
      ),
      findsOneWidget,
    );
    expect(find.text('L\'argent trouvé couvre ce besoin.'), findsOneWidget);
    expect(
      find.text(
        'Ces calculs t\'aident à réfléchir. Ils ne disent pas si ton '
        'projet réussira.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a refused amount says why; delete goes to the trash with '
      'undo', (tester) async {
    await launch(tester, AppRoutes.finances);
    await tap(tester, find.text('Ajouter').first);
    await fill(tester, 'Ce que c\'est', 'Huile');
    await fill(tester, 'Montant en ariary', '1,5');
    await tapText(tester, 'Enregistrer');
    expect(
      find.text('Vérifie le nom (80 caractères au plus) et le montant.'),
      findsOneWidget,
    );
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
        .hideCurrentSnackBar();
    await tester.pumpAndSettle();

    await soapWorkshop(tester);
    await tester.pumpAndSettle();
    await tap(tester, find.byTooltip('Supprimer').first);
    expect(find.text('Huile'), findsNothing);
    await tapText(tester, 'Annuler');
    expect(find.text('Huile'), findsOneWidget);
  });

  testWidgets('cash month by month, with the month money runs out', (
    tester,
  ) async {
    await launch(tester, AppRoutes.finances);
    await soapWorkshop(tester);
    await tester.runAsync(
      () => FinanceService(
        db,
      ).savePlan(projectId, priceMga: 1000, volumeFirst: 100, volumeLast: 400),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Pour payer tes frais du mois, vends au moins 300 unités par '
        'mois (${ar('300${nnbsp}000')} de ventes).',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Avec l\'argent trouvé, il en manque dès le départ.'),
      findsOneWidget,
    );
    expect(find.textContaining('il te manque encore'), findsOneWidget);
    expect(find.textContaining('serait remboursé en'), findsOneWidget);

    await tapText(tester, 'Voir mois par mois');
    expect(
      find.widgetWithText(AppBar, 'Trésorerie mois par mois'),
      findsOneWidget,
    );
    expect(
      find.text('Au départ, après les achats : −${ar('300${nnbsp}000')}'),
      findsOneWidget,
    );
    expect(find.text('Mois 1'), findsOneWidget);
    expect(find.text('100 unités vendues'), findsOneWidget);
    expect(
      find.text('Reste en fin de mois : −${ar('380${nnbsp}000')}'),
      findsOneWidget,
    );
  });

  testWidgets('the financing guide names kinds of money, no institution', (
    tester,
  ) async {
    await launch(tester, AppRoutes.financing);
    expect(find.widgetWithText(AppBar, 'Trouver de l\'argent'), findsOneWidget);
    expect(find.text('Les sources possibles'), findsOneWidget);
    expect(
      find.textContaining('ne cite encore aucun organisme'),
      findsOneWidget,
    );
  });

  group('calculators', () {
    testWidgets('price: pre-filled cost, margin typed, competitors compared, '
        'price kept for the project', (tester) async {
      await launch(tester, AppRoutes.priceCalculator);
      await soapWorkshop(tester);
      await tester.runAsync(
        () => CompetitorService(db).add(
          projectId: projectId,
          name: 'Épicerie A',
          kind: CompetitorKind.direct,
          priceMga: 900,
        ),
      );
      // Re-open so the fields are pre-filled with the new numbers.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      container.read(routerProvider).go(AppRoutes.project);
      await tester.pumpAndSettle();
      container.read(routerProvider).go(AppRoutes.priceCalculator);
      await tester.pumpAndSettle();

      expect(
        find.text('Remplis les cases pour voir le résultat.'),
        findsOneWidget,
      );
      await fill(tester, 'Part du prix qui doit te rester', '40');
      expect(
        find.text('Prix conseillé : ${ar('1${nnbsp}000')}'),
        findsOneWidget,
      );
      expect(find.textContaining('+66,7$nbsp% sur ton coût'), findsOneWidget);
      expect(
        find.text(
          'Ton prix est au-dessus du plus cher : qu\'apportes-tu de '
          'plus ?',
        ),
        findsOneWidget,
      );
      await fill(tester, 'Part du prix qui doit te rester', 'beaucoup');
      expect(find.text('Nombre non valide.'), findsWidgets);
      await fill(tester, 'Part du prix qui doit te rester', '40');
      await tapText(tester, 'Choisir ce prix pour mon projet');
      expect(find.text('Prix enregistré dans tes chiffres.'), findsOneWidget);
      final plan = await tester.runAsync(
        () => FinanceService(db).planOf(projectId),
      );
      expect(plan!.priceMga, 1000);
    });

    testWidgets('margin: a loss is said plainly', (tester) async {
      await launch(tester, AppRoutes.marginCalculator);
      await fill(tester, 'Prix de vente, en ariary', '500');
      await fill(tester, 'Ce que coûte une unité', '600');
      expect(
        find.text(
          'Attention : chaque unité vendue te fait perdre '
          '${ar('100')}.',
        ),
        findsOneWidget,
      );
      await fill(tester, 'Prix de vente, en ariary', '1000');
      await fill(tester, 'Ce que coûte une unité', '750');
      expect(find.text('Il te reste ${ar('250')} par unité.'), findsOneWidget);
      expect(
        find.text(
          'Soit 25$nbsp% du prix de vente, ou +33,3$nbsp% sur le '
          'coût.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('break-even: per month, per day, and when impossible', (
      tester,
    ) async {
      await launch(tester, AppRoutes.breakEvenCalculator);
      await fill(tester, 'Frais fixes d\'un mois', '120000');
      await fill(tester, 'Prix de vente, en ariary', '1000');
      await fill(tester, 'Ce que coûte une unité', '600');
      expect(
        find.textContaining('au moins 300 unités par mois'),
        findsOneWidget,
      );
      expect(find.text('Environ 10 par jour sur 30 jours.'), findsOneWidget);
      await fill(tester, 'Prix de vente, en ariary', '600');
      expect(
        find.text(
          'À ce prix, aucune quantité ne paie tes frais : chaque '
          'unité ne rapporte rien ou fait perdre.',
        ),
        findsOneWidget,
      );
    });
  });
}
