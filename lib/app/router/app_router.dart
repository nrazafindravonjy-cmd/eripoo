import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../shell/app_shell.dart';
import '../shell/section_placeholder_screen.dart';

/// Top-level route paths.
abstract final class AppRoutes {
  static const home = '/home';
  static const quest = '/quest';
  static const project = '/project';
  static const tools = '/tools';
  static const profile = '/profile';
}

/// Application router. Redirects will depend on local state only
/// (onboarding, diagnostic — Phase 2), never on the network or on sign-in.
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          _branch(AppRoutes.home, (l10n) => l10n.navHome),
          _branch(AppRoutes.quest, (l10n) => l10n.navQuest),
          _branch(AppRoutes.project, (l10n) => l10n.navProject),
          _branch(AppRoutes.tools, (l10n) => l10n.navTools),
          _branch(AppRoutes.profile, (l10n) => l10n.navProfile),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

StatefulShellBranch _branch(
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
