import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../content/content_pack.dart';
import '../../../content/localized_text.dart';
import '../../../content/planner.dart';
import '../../../core/i18n/app_language.dart';
import '../../../data/local/app_database.dart';
import '../../missions/domain/mission_state.dart';
import '../../project/data/project_repository.dart';
import '../../project/domain/project.dart';
import '../application/journey_service.dart';

/// The encrypted local database (opened by bootstrap; overridden in tests).
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => ref.watch(appServicesProvider).database,
);

/// Asset of the content pack embedded in the app.
const basePackAsset = 'assets/content/base_pack.json';

/// The content pack embedded in the app (loaded by bootstrap).
final contentPackProvider = Provider<ContentPack>(
  (ref) => throw UnimplementedError('Loaded by bootstrap()'),
);

final journeyServiceProvider = Provider<JourneyService>(
  (ref) => JourneyService(
    pack: ref.watch(contentPackProvider),
    db: ref.watch(appDatabaseProvider),
  ),
);

final journeyPlanProvider = StreamProvider<JourneyPlan>(
  (ref) => ref.watch(journeyServiceProvider).watchPlan(),
);

final missionsProvider = StreamProvider<List<MissionInstance>>(
  (ref) => ref.watch(journeyServiceProvider).watchMissions(),
);

final activeProjectProvider = StreamProvider<Project?>(
  (ref) =>
      ProjectRepository(ref.watch(appDatabaseProvider))
          .watchActive()
          .map((projects) => projects.isEmpty ? null : projects.first),
);

/// Content texts in the language of the interface.
ContentLocalizer contentLocalizerOf(BuildContext context) => ContentLocalizer(
  AppLanguage.tryParse(Localizations.localeOf(context).languageCode) ??
      AppLanguage.fr,
);
