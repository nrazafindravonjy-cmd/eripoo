// The trash and "versions to check" through the real UI. Fictitious data.
import 'dart:convert';
import 'dart:io';

import 'package:eripoo/app/app.dart';
import 'package:eripoo/app/di/core_providers.dart';
import 'package:eripoo/app/router/app_router.dart';
import 'package:eripoo/core/i18n/app_language.dart';
import 'package:eripoo/core/ids/ids.dart';
import 'package:eripoo/data/local/app_database.dart';
import 'package:eripoo/design_system/design_system.dart';
import 'package:eripoo/features/hypotheses/application/research_service.dart';
import 'package:eripoo/features/hypotheses/presentation/research_providers.dart';
import 'package:eripoo/features/media/data/media_store.dart';
import 'package:eripoo/features/project/data/project_repository.dart';
import 'package:eripoo/features/settings/domain/app_settings.dart';
import 'package:eripoo/features/settings/presentation/app_settings_controller.dart';
import 'package:eripoo/features/trash/application/trash_service.dart';
import 'package:eripoo/security/crypto_service.dart';
import 'package:eripoo/sync/engine/entity_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/journey_overrides.dart';
import '../../helpers/memory_secure_store.dart';
import '../../helpers/test_database.dart';
import '../../helpers/test_host.dart';

void main() {
  late CryptoService crypto;
  late AppDatabase db;
  late Directory mediaDir;
  late String projectId;

  setUpAll(() async => crypto = await CryptoService.init());
  setUp(() {
    db = memoryDatabase();
    mediaDir = Directory.systemTemp.createTempSync('eripoo_ui_trash');
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
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> hideSnackBar(WidgetTester tester) async {
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
        .hideCurrentSnackBar();
    await tester.pumpAndSettle();
  }

  testWidgets('delete, undo, delete again, restore from the trash, then '
      'delete for good', (tester) async {
    final container = await launch(tester, AppRoutes.fieldNotes);
    await tester.runAsync(
      () => ResearchService(db).addObservation(
        projectId: projectId,
        description: 'File d\'attente à la fontaine.',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('File d\'attente à la fontaine.'), findsOneWidget);

    await tap(tester, find.text('Supprimer').first);
    expect(find.text('File d\'attente à la fontaine.'), findsNothing);
    expect(find.text('Mis à la corbeille.'), findsOneWidget);
    await tap(tester, find.text('Annuler'));
    expect(find.text('File d\'attente à la fontaine.'), findsOneWidget);
    await hideSnackBar(tester);

    await tap(tester, find.text('Supprimer').first);
    await hideSnackBar(tester);
    container.read(routerProvider).go(AppRoutes.project);
    await tester.pumpAndSettle();
    await tap(tester, find.text('Corbeille (1)'));
    expect(find.text('File d\'attente à la fontaine.'), findsOneWidget);
    expect(find.textContaining('effacé pour de bon le'), findsOneWidget);

    await tap(tester, find.text('Remettre'));
    expect(find.text('La corbeille est vide.'), findsOneWidget);

    await tester.runAsync(() async {
      final id = (await ResearchService(db).observationsOf(projectId))
          .single
          .id;
      await TrashService(db).moveToTrash(TrashKind.observation, id);
    });
    await tester.pumpAndSettle();
    await tap(tester, find.text('Supprimer pour de bon'));
    expect(find.text('Supprimer pour de bon ?'), findsOneWidget);
    await tap(tester, find.text('Supprimer pour de bon').last);
    expect(find.text('La corbeille est vide.'), findsOneWidget);
    final left = await tester.runAsync(() => db.select(db.observations).get());
    expect(left, isEmpty, reason: 'never synced: deleted at once');
  });

  testWidgets('versions to check: keep the other version', (tester) async {
    await launch(tester, AppRoutes.conflicts);
    expect(find.text('Rien à vérifier.'), findsOneWidget);

    await tester.runAsync(() async {
      final current = (await EntityRegistry(db).read('project', projectId))!;
      final now = DateTime.now().millisecondsSinceEpoch;
      await db
          .into(db.conflictCopies)
          .insert(
            ConflictCopiesCompanion.insert(
              id: Ids.newId(),
              entityType: 'project',
              entityId: projectId,
              payloadJson: jsonEncode({
                ...current,
                'title': 'Savon et bougies',
              }),
              createdAt: now,
              updatedAt: now,
            ),
          );
    });
    await tester.pumpAndSettle();
    expect(find.widgetWithText(EripooCard, 'Projet'), findsOneWidget);
    expect(find.text('Savon du quartier'), findsOneWidget);
    expect(find.text('Savon et bougies'), findsOneWidget);

    await tap(tester, find.text('Garder l\'autre version'));
    expect(find.text('Rien à vérifier.'), findsOneWidget);
    final project = await tester.runAsync(
      () => ProjectRepository(db).get(projectId),
    );
    expect(project!.title, 'Savon et bougies');
  });
}
