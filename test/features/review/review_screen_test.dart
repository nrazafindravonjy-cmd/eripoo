// Points to review through the real UI: shown on the Project screen only
// when there is one, explained with the user's numbers, and leading to
// where it can be fixed. Fictitious data only.
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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/journey_overrides.dart';
import '../../helpers/memory_secure_store.dart';
import '../../helpers/test_database.dart';
import '../../helpers/test_host.dart';

void main() {
  late CryptoService crypto;
  late AppDatabase db;
  late Directory tmp;

  setUpAll(() async => crypto = await CryptoService.init());
  setUp(() {
    db = memoryDatabase();
    tmp = Directory.systemTemp.createTempSync('eripoo_ui_review');
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<void> launch(
    WidgetTester tester,
    Future<void> Function(String projectId) work,
  ) async {
    setSurfaceSize(tester, phoneSize);
    await tester.runAsync(() async {
      final id = (await ProjectRepository(db).create('Savon du quartier')).id;
      await work(id);
    });
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
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const EripooApp()),
    );
    await tester.pumpAndSettle();
    container.read(routerProvider).go(AppRoutes.project);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('nothing to review: no entry on the Project screen', (
    tester,
  ) async {
    await launch(tester, (_) async {});
    expect(find.textContaining('à revoir'), findsNothing);
  });

  testWidgets('a price below cost: counted, explained, and leads to the '
      'finances', (tester) async {
    await launch(tester, (id) async {
      final f = FinanceService(db);
      await f.add(
        projectId: id,
        kind: FinanceKind.variableCost,
        label: 'Huile et soude',
        amountMga: 1200,
      );
      await f.savePlan(id, priceMga: 1000, volumeFirst: null, volumeLast: null);
      await ProjectRepository(db).saveSection(
        projectId: id,
        sectionKey: 'solution',
        fields: {'first_idea': 'Savon livré au marché'},
      );
    });
    await tap(tester, find.text('2 points à revoir'));
    expect(find.text('Points à revoir'), findsOneWidget);
    expect(
      find.textContaining('Eripoo compare ce que tu as noté'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Ton prix (1\u202f000\u00a0Ar) est plus bas que ce que coûte une '
        'unité (1\u202f200\u00a0Ar) : chaque vente te fait perdre de '
        'l\'argent.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Tu décris une solution, mais pas encore pour qui elle est.'),
      findsOneWidget,
    );
    await tap(tester, find.text('Revoir').first);
    expect(find.text('Points à revoir'), findsNothing);
  });
}
