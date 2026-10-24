// The canvas, the file, the pitch and the pitch deck through the real UI,
// and the PDF export (warning first, file deleted after sharing).
// Fictitious data only.
import 'dart:io';

import 'package:eripoo/app/app.dart';
import 'package:eripoo/app/di/core_providers.dart';
import 'package:eripoo/app/router/app_router.dart';
import 'package:eripoo/core/i18n/app_language.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/documents/presentation/pdf_export.dart';
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

import '../../helpers/activate.dart';
import '../../helpers/journey_overrides.dart';
import '../../helpers/memory_secure_store.dart';
import '../../helpers/test_database.dart';
import '../../helpers/test_host.dart';

class _FakeSharer implements PdfSharer {
  final shared = <(String, List<int>)>[];

  @override
  Future<void> share(File file, String title) async {
    shared.add((file.path, await file.readAsBytes()));
  }
}

void main() {
  late CryptoService crypto;
  late AppDatabase db;
  late Directory tmp;
  late String projectId;
  late _FakeSharer sharer;

  setUpAll(() async => crypto = await CryptoService.init());
  setUp(() {
    db = memoryDatabase();
    tmp = Directory.systemTemp.createTempSync('eripoo_ui_docs');
    sharer = _FakeSharer();
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
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
            dir: Directory('${tmp.path}/media')..createSync(),
          ),
        ),
        pdfSharerProvider.overrideWithValue(sharer),
        exportDirProvider.overrideWith(
          (ref) async => Directory('${tmp.path}/export'),
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

  Future<void> work(WidgetTester tester) => tester.runAsync(() async {
    final projects = ProjectRepository(db);
    await projects.saveSection(
      projectId: projectId,
      sectionKey: 'customers',
      fields: {'description': 'Vendeuses du marché'},
    );
    await projects.saveSection(
      projectId: projectId,
      sectionKey: 'solution',
      fields: {'first_idea': 'Savon livré au marché'},
    );
    final f = FinanceService(db);
    await f.add(
      projectId: projectId,
      kind: FinanceKind.variableCost,
      label: 'Huile',
      amountMga: 600,
    );
    await f.savePlan(
      projectId,
      priceMga: 1000,
      volumeFirst: null,
      volumeLast: null,
    );
  });

  testWidgets('canvas: built blocks first, then what is left and where; a '
      'block is completed from the canvas', (tester) async {
    await launch(tester, AppRoutes.canvas);
    expect(find.text('Cases remplies : 0 / 9'), findsOneWidget);
    expect(find.text('Encore à construire'), findsOneWidget);

    await work(tester);
    await tester.pumpAndSettle();
    expect(find.text('Cases remplies : 4 / 9'), findsOneWidget);
    expect(find.text('Vendeuses du marché'), findsOneWidget);
    expect(find.text('Prix : 1 000 Ar'), findsOneWidget);
    expect(find.text('Huile : 600 Ar'), findsOneWidget);

    await tap(tester, find.text('Qui t\'aide'));
    await fill(tester, 'Qui t\'aide (fournisseurs', 'Coopérative d\'huile');
    await tapText(tester, 'Enregistrer');
    expect(find.text('Cases remplies : 5 / 9'), findsOneWidget);
    expect(find.text('Coopérative d\'huile'), findsOneWidget);
  });

  testWidgets('file: ready chapters, chapters left, and an export that '
      'warns, shares, then deletes the file', (tester) async {
    await launch(tester, AppRoutes.businessPlan);
    await work(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Chapitres prêts : '), findsOneWidget);
    expect(find.text('Encore à travailler'), findsOneWidget);
    expect(find.text('Écris ton pitch.'), findsOneWidget);

    await tapText(tester, 'Partager en PDF');
    expect(find.text('Partager un PDF'), findsOneWidget);
    await tapText(tester, 'Annuler');
    expect(sharer.shared, isEmpty, reason: 'cancelled: nothing written');

    await tapText(tester, 'Partager en PDF');
    await tester.tap(find.text('Continuer').last);
    // Fonts are read and the PDF built on another isolate: real time.
    for (var i = 0; i < 100 && sharer.shared.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(sharer.shared, hasLength(1));
    final (path, bytes) = sharer.shared.single;
    expect(path, endsWith('Savon_du_quartier_dossier.pdf'));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    for (var i = 0; i < 40 && File(path).existsSync(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(File(path).existsSync(), isFalse, reason: 'deleted after sharing');
  });

  testWidgets('pitch: written in its section, timed out loud', (tester) async {
    await launch(tester, AppRoutes.pitch);
    expect(find.text('Une phrase pour accrocher'), findsNothing);
    await tapText(tester, 'Modifier');
    await fill(
      tester,
      'Une phrase pour accrocher',
      'Les vendeuses perdent '
          'une heure par semaine pour acheter du savon.',
    );
    await tapText(tester, 'Enregistrer');
    expect(find.textContaining('À voix haute : environ'), findsOneWidget);
    expect(find.textContaining('Plus d\'une minute'), findsNothing);
  });

  testWidgets('pitch deck: a cover and only slides with content', (
    tester,
  ) async {
    await launch(tester, AppRoutes.pitchDeck);
    expect(find.text('1 diapositive'), findsOneWidget);
    await work(tester);
    await tester.pumpAndSettle();
    expect(find.text('5 diapositives'), findsOneWidget);
    expect(find.text('Pour qui'), findsOneWidget);
    expect(find.text('Comment on gagne de l\'argent'), findsOneWidget);
    expect(find.text('Ce que nous demandons'), findsNothing);
  });

  test('purge: our exports and the share sheet copy go at start-up', () async {
    final export = Directory('${tmp.path}/export')..createSync();
    File('${export.path}/a.pdf').writeAsStringSync('x');
    final shareCopy = Directory('${tmp.path}/share_plus')..createSync();
    File('${shareCopy.path}/a.pdf').writeAsStringSync('x');
    await purgeExports(export);
    expect(export.existsSync(), isFalse);
    expect(shareCopy.existsSync(), isFalse);
    await purgeExports(export);
  });
}
