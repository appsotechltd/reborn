import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'api/models.dart';
import 'data/providers.dart';
import 'features/ask/ask_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/auth/forgot_password_screen.dart';
import 'features/card/card_screen.dart';
import 'features/comments/comments_screen.dart';
import 'features/contribute/contribute_screen.dart';
import 'features/contribute/my_contributions_screen.dart';
import 'features/daily/daily_screen.dart';
import 'features/home/home_screen.dart';
import 'features/moderation/moderation_screen.dart';
import 'features/onboarding/topic_picker_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/review/quiz_screen.dart';
import 'features/review/review_screen.dart';
import 'features/search/search_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/social/author_screen.dart';
import 'features/social/favorites_screen.dart';
import 'features/social/following_screen.dart';
import 'features/social/user_profile_screen.dart';
import 'features/source/source_screen.dart';
import 'features/stashes/stash_detail_screen.dart';
import 'features/stashes/stashes_screen.dart';
import 'features/timeline/timeline_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/home',
    redirect: (context, state) {
      final onboarded =
          ref.read(topicPrefsProvider.notifier).onboarded ||
          ref.read(sessionProvider).signedIn;
      if (!onboarded && state.matchedLocation != '/onboarding') {
        return '/onboarding';
      }
      if (state.matchedLocation == '/') return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (_, _) => const TopicPickerScreen(),
      ),
      GoRoute(
        path: '/topics',
        builder: (_, _) => const TopicPickerScreen(onboarding: false),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const TimelineScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/stashes',
                builder: (_, _) => const StashesScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (_, s) =>
                        StashDetailScreen(stashId: s.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/review',
                builder: (_, _) => const ReviewScreen(),
                routes: [
                  GoRoute(path: 'quiz', builder: (_, _) => const QuizScreen()),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/ask', builder: (_, _) => const AskScreen()),
            ],
          ),
        ],
      ),
      GoRoute(path: '/feed', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/daily', builder: (_, _) => const DailyScreen()),
      GoRoute(
        path: '/cards/:id',
        builder: (_, s) => CardScreen(
          cardId: s.pathParameters['id']!,
          initial: s.extra is IdeaCard ? s.extra as IdeaCard : null,
        ),
      ),
      GoRoute(
        path: '/posts/:id/comments',
        builder: (_, s) => CommentsScreen(
          postId: s.pathParameters['id']!,
          post: s.extra is Post ? s.extra as Post : null,
        ),
      ),
      GoRoute(
        path: '/users/:handle',
        builder: (_, s) =>
            UserProfileScreen(handle: s.pathParameters['handle']!),
      ),
      GoRoute(
        path: '/authors/:name',
        builder: (_, s) => AuthorScreen(name: s.pathParameters['name']!),
      ),
      GoRoute(path: '/favorites', builder: (_, _) => const FavoritesScreen()),
      GoRoute(path: '/following', builder: (_, _) => const FollowingScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(
        path: '/forgot',
        builder: (_, s) => ForgotPasswordScreen(
          email: s.extra is String ? s.extra as String : null,
        ),
      ),
      GoRoute(
        path: '/sources/:id',
        builder: (_, s) => SourceScreen(sourceId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/signin', builder: (_, _) => const AuthScreen()),
      GoRoute(
        path: '/register',
        builder: (_, _) => const AuthScreen(register: true),
      ),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      GoRoute(path: '/contribute', builder: (_, _) => const ContributeScreen()),
      GoRoute(
        path: '/contributions',
        builder: (_, _) => const MyContributionsScreen(),
      ),
      GoRoute(path: '/moderation', builder: (_, _) => const ModerationScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
