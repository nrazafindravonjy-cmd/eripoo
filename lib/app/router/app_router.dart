import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/presentation/home_screen.dart';
import '../../features/missions/presentation/mission_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/quest/presentation/quest_screens.dart';
import '../../features/quest/presentation/step_screen.dart';
import '../../features/settings/presentation/app_settings_controller.dart';
import '../../l10n/generated/app_localizations.dart';
import '../shell/app_shell.dart';
import '../shell/section_placeholder_screen.dart';

/// Top-level route paths.
abstract final class AppRoutes {
  static const welcome = '/welcome';
  static const home = '/home';
  static const quest = '/quest';
  static const project = '/project';
  static const tools = '/tools';
  static const profile = '/profile';

  static String questDetail(String questId) => '$quest/$questId';
  static String step(String stepId) => '/step/$stepId';
  static String mission(String missionId) => '/mission/$missionId';
}

/// Application router. Redirects depend on local state only (the language
/// chosen on the welcome screen), never on the network or on sign-in.
final routerProvider = Provider<GoRouter>((ref) {
  final languageChosen = ValueNotifier<bool>(
    ref.read(appSettingsProvider).language != null,
  );
  ref.listen(
    appSettingsProvider.select((s) => s.language != null),
    (_, chosen) => languageChosen.value = chosen,
  );
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    refreshListenable: languageChosen,
    redirect: (context, state) {
      final atWelcome = state.matchedLocation == AppRoutes.welcome;
      if (!languageChosen.value) return atWelcome ? null : AppRoutes.welcome;
      return atWelcome ? AppRoutes.home : null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/step/:stepId',
        builder: (context, state) =>
            StepScreen(stepId: state.pathParameters['stepId']!),
      ),
      GoRoute(
        path: '/mission/:missionId',
        builder: (context, state) =>
            MissionScreen(missionId: state.pathParameters['missionId']!),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.quest,
                builder: (context, state) => const QuestListScreen(),
                routes: [
                  GoRoute(
                    path: ':questId',
                    builder: (context, state) => QuestDetailScreen(
                      questId: state.pathParameters['questId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          _placeholder(AppRoutes.project, (l10n) => l10n.navProject),
          _placeholder(AppRoutes.tools, (l10n) => l10n.navTools),
          _placeholder(AppRoutes.profile, (l10n) => l10n.navProfile),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    languageChosen.dispose();
  });
  return router;
});

/// Sections built in later phases.
StatefulShellBranch _placeholder(
  String path,
  String Function(AppLocalizations) title,
) => StatefulShellBranch(
  routes: [
    GoRoute(
      path: path,
      builder: (context, state) =>
          SectionPlaceholderScreen(title: title(AppLocalizations.of(context))),
    ),
  ],
);
