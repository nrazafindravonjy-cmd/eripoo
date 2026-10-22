// The Project screens, through the real UI: sections with "before / now",
// a hypothesis tested to its conclusion with an encrypted photo as
// evidence, and the field notebook. Fictitious data only.
import 'dart:io';
import 'dart:typed_data';

import 'package:eripoo/app/app.dart';
import 'package:eripoo/app/di/core_providers.dart';
import 'package:eripoo/app/router/app_router.dart';
import 'package:eripoo/core/i18n/app_language.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/design_system/design_system.dart';
import 'package:eripoo/features/hypotheses/domain/research.dart';
import 'package:eripoo/features/hypotheses/presentation/research_providers.dart';
import 'package:eripoo/features/media/application/photo_source.dart';
import 'package:eripoo/features/media/data/media_store.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/features/settings/domain/app_settings.dart';
import 'package:eripoo/features/settings/presentation/app_settings_controller.dart';
import 'package:eripoo/security/crypto_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/journey_overrides.dart';
import '../../helpers/memory_secure_store.dart';
import '../../helpers/test_database.dart';
import '../../helpers/test_host.dart';

class _FakePhotos implements PhotoSource {
  int taken = 0;
  @override
  Future<PickedPhoto?> take() async {
    taken++;
    return PickedPhoto(
      Uint8List.fromList([0xff, 0xd8, 0xff, ...List.filled(64, 7)]),
      'image/jpeg',
    );
  }

  @override
  Future<PickedPhoto?> choose() async => null;
}

void main() {
  late CryptoService crypto;
  late AppDatabase db;
  late Directory mediaDir;
  late _FakePhotos photos;
  late String projectId;

  setUpAll(() async => crypto = await CryptoService.init());
  setUp(() {
    db = memoryDatabase();
    mediaDir = Directory.systemTemp.createTempSync('eripoo_ui_media');
    photos = _FakePhotos();
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
        photoSourceProvider.overrideWithValue(photos),
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
    final field = find.widgetWithText(TextField, label).last;
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
    await tester.pumpAndSettle();
  }

  testWidgets('a hypothesis from draft to conclusion, with an encrypted '
      'photo, then a new version', (tester) async {
    final container = await launch(tester, AppRoutes.hypotheses);
    expect(find.textContaining('pas encore vérifié'), findsOneWidget);

    // ---- create
    await tapText(tester, 'Nouvelle hypothèse');
    await fill(
      tester,
      'Ce que tu penses',
      'Les vendeuses manquent de temps pour acheter du savon.',
    );
    await tapText(tester, 'Le projet en dépend');
    await tapText(tester, 'Enregistrer');
    await tapText(
      tester,
      'Les vendeuses manquent de temps pour acheter du savon.',
    );
    expect(find.text('Brouillon'), findsOneWidget);

    // ---- plan a test without criterion: starting it is refused
    await tapText(tester, 'Préparer un test');
    await tapText(tester, 'Discuter avec des personnes');
    await fill(tester, 'Ce que tu vas faire', 'Parler à 5 vendeuses.');
    await tapText(tester, 'Enregistrer');
    expect(find.text('À tester'), findsOneWidget);
    await tapText(tester, 'Commencer le test');
    expect(
      find.text('Écris d\'abord quand le test sera réussi.'),
      findsOneWidget,
    );

    // ---- set the criterion, start: locked
    await tapText(tester, 'Modifier');
    await fill(tester, 'Le test est réussi si…', 'Au moins 3 sur 5.');
    await tapText(tester, 'Enregistrer');
    await tapText(tester, 'Commencer le test');
    expect(find.text('En test'), findsOneWidget);
    expect(find.text('Fixé avant le test : Au moins 3 sur 5.'), findsOneWidget);

    // ---- concluding too early is refused, with a clear message
    await tapText(tester, 'Conclure');
    await fill(tester, 'Ce que tu penses maintenant', 'Oui');
    await tap(tester, find.widgetWithText(EripooButton, 'Conclure').last);
    expect(find.text('Note d\'abord au moins un résultat.'), findsOneWidget);
    await tester.binding.handlePopRoute(); // Android back closes the sheet
    await tester.pumpAndSettle();
    // The message disappears by itself after a few seconds.
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
        .hideCurrentSnackBar();
    await tester.pumpAndSettle();

    // ---- a result, then a photo as evidence (encrypted on disk)
    await tapText(tester, 'Noter un résultat');
    await fill(tester, 'Ce que tu as observé', '4 vendeuses sur 5 en parlent.');
    await fill(tester, 'Combien ont dit oui (facultatif)', '4');
    await fill(tester, 'Sur combien (facultatif)', '5');
    await tapText(tester, 'Enregistrer');
    expect(find.text('4 sur 5'), findsOneWidget);

    await tapText(tester, 'Ajouter une preuve');
    await tapText(tester, 'Photo');
    await tapText(tester, 'Prendre une photo');
    expect(photos.taken, 1);
    expect(find.byType(Image), findsOneWidget);
    final files = mediaDir.listSync();
    expect(files, hasLength(1));
    expect(
      (files.single as File).readAsBytesSync().sublist(0, 3),
      isNot([0xff, 0xd8, 0xff]),
    );

    // ---- conclude: validated
    await tapText(tester, 'Conclure');
    await fill(
      tester,
      'Ce que tu penses maintenant',
      'Le manque de temps est réel.',
    );
    await tapText(tester, '4');
    await tap(tester, find.widgetWithText(EripooButton, 'Conclure').last);
    expect(find.text('Confirmée'), findsWidgets);
    expect(find.text('Confiance : 3 → 4'), findsOneWidget);

    // ---- decide: modify creates a linked version
    await tapText(tester, 'Décider la suite');
    expect(find.text('Abandonner'), findsNothing); // not on validated
    await tapText(tester, 'Modifier l\'hypothèse');
    await fill(
      tester,
      'La nouvelle version',
      'Les vendeuses manquent de temps le matin.',
    );
    await fill(tester, 'Pourquoi ?', 'Le soir, elles ont le temps.');
    await tapText(tester, 'Enregistrer');
    expect(find.text('Nouvelle version'), findsOneWidget);
    await tapText(tester, 'Nouvelle version');
    expect(
      find.text('Les vendeuses manquent de temps le matin.'),
      findsWidgets,
    );
    expect(find.text('Version précédente'), findsOneWidget);

    final list = await tester.runAsync(
      () => container.read(researchServiceProvider).hypothesesOf(projectId),
    );
    expect(list!.map((h) => h.status), [
      HypothesisStatus.validated,
      HypothesisStatus.draft,
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('project sections: edit by hand, "before / now" kept', (
    tester,
  ) async {
    await launch(tester, AppRoutes.project);
    expect(find.text('Le problème'), findsOneWidget);
    expect(
      find.text('Pas encore rempli : les quêtes t\'aideront.'),
      findsWidgets,
    );
    await tap(tester, find.text('Modifier').first);
    await fill(
      tester,
      'Le problème observé (facultatif)',
      'Les mères perdent une heure.',
    );
    await tapText(tester, 'Enregistrer');
    expect(find.text('Les mères perdent une heure.'), findsOneWidget);

    await tap(tester, find.text('Modifier').first);
    await fill(
      tester,
      'Le problème observé (facultatif)',
      'Les mères manquent d\'eau.',
    );
    await tapText(tester, 'Enregistrer');
    await tap(tester, find.text('Avant / Maintenant').first);
    expect(find.text('Avant : Les mères perdent une heure.'), findsOneWidget);
    expect(
      find.text('Maintenant : Les mères manquent d\'eau.'),
      findsOneWidget,
    );
    expect(find.text('Avant : (vide)'), findsOneWidget);
  });

  testWidgets('field notebook: observation and interview, pseudonym only', (
    tester,
  ) async {
    await launch(tester, AppRoutes.fieldNotes);
    await tapText(tester, 'Noter une rencontre');
    expect(
      find.text(
        'Pas d\'enregistrement de la personne : prends des notes '
        'écrites.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Pas de vrai nom ni de numéro de téléphone.'),
      findsOneWidget,
    );
    await fill(tester, 'Surnom de la personne', 'Vendeuse A');
    await fill(
      tester,
      'Ce que la personne t\'a dit',
      'Elle achète le dimanche.',
    );
    await tapText(tester, 'Enregistrer');
    expect(find.text('Vendeuse A'), findsOneWidget);

    await tapText(tester, 'Noter une observation');
    await fill(tester, 'Ce que tu as vu', 'File d\'attente à la fontaine.');
    await tapText(tester, 'Enregistrer');
    expect(find.text('File d\'attente à la fontaine.'), findsOneWidget);

    await tap(tester, find.text('Ajouter une preuve').first);
    await tapText(tester, 'Vente');
    await fill(tester, 'Montant en ariary', '15 000');
    await tapText(tester, 'Enregistrer');
    expect(find.textContaining('15'), findsWidgets);
  });
}
