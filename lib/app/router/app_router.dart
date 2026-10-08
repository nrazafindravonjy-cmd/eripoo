import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/presentation/profile_screen.dart';
import '../../features/conflicts/presentation/conflicts_screen.dart';
import '../../features/finance/presentation/calculators_screen.dart';
import '../../features/finance/presentation/cash_plan_screen.dart';
import '../../features/finance/presentation/finances_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/hypotheses/presentation/field_notes_screen.dart';
import '../../features/hypotheses/presentation/hypotheses_screen.dart';
import '../../features/hypotheses/presentation/hypothesis_screen.dart';
import '../../features/missions/presentation/mission_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/project/presentation/project_screen.dart';
import '../../features/quest/presentation/quest_screens.dart';
import '../../features/quest/presentation/step_screen.dart';
import '../../features/settings/presentation/app_settings_controller.dart';
import '../../features/tools/presentation/competitors_screen.dart';
import '../../features/tools/presentation/interview_guide_screen.dart';
import '../../features/tools/presentation/tools_screen.dart';
import '../../features/trash/presentation/trash_screen.dart';
import '../shell/app_shell.dart';

/// Top-level route paths.
abstract final class AppRoutes {
  static const welcome = '/welcome';
  static const home = '/home';
  static const quest = '/quest';
  static const project = '/project';
  static const tools = '/tools';
  static const profile = '/profile';

  static const hypotheses = '/project/hypotheses';
  static const fieldNotes = '/project/notes';
  static const trash = '/project/trash';
  static const conflicts = '/project/versions';
  static const interviewGuide = '/tools/interview-guide';
  static const competitors = '/tools/competitors';
  static const priceCalculator = '/tools/price';
  static const marginCalculator = '/tools/margin';
  static const breakEvenCalculator = '/tools/break-even';
  static const finances = '/project/finances';
  static const cashPlan = '/project/finances/cash';
  static const financing = '/project/finances/financing';

  static String questDetail(String questId) => '$quest/$questId';
  static String hypothesis(String id) => '$hypotheses/$id';
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
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.project,
                builder: (context, state) => const ProjectScreen(),
                routes: [
                  GoRoute(
                    path: 'hypotheses',
                    builder: (context, state) => const HypothesesScreen(),
                    routes: [
                      GoRoute(
                        path: ':hypothesisId',
                        builder: (context, state) => HypothesisScreen(
                          hypothesisId: state.pathParameters['hypothesisId']!,
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'notes',
                    builder: (context, state) => const FieldNotesScreen(),
                  ),
                  GoRoute(
                    path: 'trash',
                    builder: (context, state) => const TrashScreen(),
                  ),
                  GoRoute(
                    path: 'versions',
                    builder: (context, state) => const ConflictsScreen(),
                  ),
                  GoRoute(
                    path: 'finances',
                    builder: (context, state) => const FinancesScreen(),
                    routes: [
                      GoRoute(
                        path: 'cash',
                        builder: (context, state) => const CashPlanScreen(),
                      ),
                      GoRoute(
                        path: 'financing',
                        builder: (context, state) =>
                            const FinancingGuideScreen(),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.tools,
                builder: (context, state) => const ToolsScreen(),
                routes: [
                  GoRoute(
                    path: 'interview-guide',
                    builder: (context, state) => const InterviewGuideScreen(),
                  ),
                  GoRoute(
                    path: 'competitors',
                    builder: (context, state) => const CompetitorsScreen(),
                  ),
                  GoRoute(
                    path: 'price',
                    builder: (context, state) => const PriceCalculatorScreen(),
                  ),
                  GoRoute(
                    path: 'margin',
                    builder: (context, state) => const MarginCalculatorScreen(),
                  ),
                  GoRoute(
                    path: 'break-even',
                    builder: (context, state) =>
                        const BreakEvenCalculatorScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
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
