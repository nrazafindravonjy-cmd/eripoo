// The administrative preparation through the real UI: dated and sourced
// information, the warning when it gets old, documents ticked and kept,
// the fee estimate, and the PDF. Fictitious data only.
import 'dart:io';

import 'package:eripoo/app/app.dart';
import 'package:eripoo/app/di/core_providers.dart';
import 'package:eripoo/app/router/app_router.dart';
import 'package:eripoo/core/i18n/app_language.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/features/documents/presentation/pdf_export.dart';
import 'package:eripoo/features/formalization/application/preparation_service.dart';
import 'package:eripoo/features/formalization/presentation/admin_preparation_screen.dart';
import 'package:eripoo/features/hypotheses/presentation/research_providers.dart';
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

class _FakeSharer implements PdfSharer {
  final shared = <List<int>>[];

  @override
  Future<void> share(File file, String title) async =>
      shared.add(await file.readAsBytes());
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
    tmp = Directory.systemTemp.createTempSync('eripoo_ui_prep');
    sharer = _FakeSharer();
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<void> launch(WidgetTester tester, {DateTime? now}) async {
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
        clockProvider.overrideWithValue(() => now ?? DateTime.utc(2026, 10, 9)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const EripooApp()),
    );
    await tester.pumpAndSettle();
    container.read(routerProvider).go(AppRoutes.adminPreparation);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

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

  testWidgets('dated, sourced, not presented as reviewed; advice is marked '
      'as advice', (tester) async {
    await launch(tester);
    expect(
      find.textContaining('lues le 8 octobre 2026 sur le site de l\'EDBM'),
      findsOneWidget,
    );
    expect(find.text('Pas encore relues par un juriste.'), findsOneWidget);
    expect(find.textContaining('plus de trois mois'), findsNothing);
    expect(
      find.text(
        'Source : EDBM — Economic Development Board of Madagascar — '
        'Création de société, Version 28 : Juillet 2026 (p. 2, Horaire)',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Conseil d\'Eripoo : Eripoo prépare ton dossier'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'pas encore de source officielle vérifiée sur '
        'l\'entreprise individuelle',
      ),
      findsOneWidget,
    );
  });

  testWidgets('after the review date, the screen says it may be out of date', (
    tester,
  ) async {
    await launch(tester, now: DateTime.utc(2027, 1, 9));
    expect(
      find.text(
        'Ces informations ont plus de trois mois : elles ont peut-être '
        'changé depuis.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('documents ticked are kept; the estimate follows the schedule; '
      'the PDF is shared', (tester) async {
    await launch(tester);
    expect(find.text('Prêtes : 0 / 13'), findsOneWidget);
    await tap(tester, find.byType(CheckboxListTile).first);
    expect(find.text('Prêtes : 1 / 13'), findsOneWidget);
    final prep = await tester.runAsync(
      () => PreparationService(db).of(projectId),
    );
    expect(prep!.ready, {'statutes'});

    expect(
      find.text(
        'Indique le capital et choisis ton activité pour voir '
        'l\'estimation.',
      ),
      findsOneWidget,
    );
    await fill(tester, 'Capital de la société', '1 000 000');
    await tap(tester, find.text('Choisir ton activité'));
    await tap(
      tester,
      find.text('Artisans, gargotiers, petits producteurs').last,
    );
    // 20 000 + 16 000 + 40 000 + 50 000
    expect(find.text('Total estimé : 126 000 Ar'), findsOneWidget);
    await fill(tester, 'Loyer par mois', '100000');
    expect(
      find.text('Vérifie les montants : le loyer et la durée vont ensemble.'),
      findsOneWidget,
    );
    await fill(tester, 'Durée du bail', '12');
    // + 2 % of 1 200 000 = 24 000
    expect(find.text('Total estimé : 150 000 Ar'), findsOneWidget);
    await tap(tester, find.text('Garder ces chiffres'));
    final kept = await tester.runAsync(
      () => PreparationService(db).of(projectId),
    );
    expect(kept!.capitalMga, 1000000);
    expect(kept.taxId, 'artisans');
    expect(kept.leaseMonths, 12);
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
        .hideCurrentSnackBar();
    await tester.pumpAndSettle();

    await tap(tester, find.text('Partager en PDF'));
    expect(find.text('Partager un PDF'), findsOneWidget);
    await tester.tap(find.text('Continuer').last);
    for (var i = 0; i < 100 && sharer.shared.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(sharer.shared, hasLength(1));
    expect(String.fromCharCodes(sharer.shared.single.take(5)), '%PDF-');
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  });
}
