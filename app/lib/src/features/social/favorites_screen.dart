import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../widgets/common.dart';
import 'post_list_controller.dart';

/// The signed-in user's favourites (GET /v1/me/favorites).
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(sessionProvider.select((s) => s.signedIn));
    return Scaffold(
      appBar: AppBar(title: const Text('Favourites')),
      body: !signedIn
          ? const SignInPrompt(
              icon: Icons.favorite_border,
              title: 'Your favourites',
              message: 'Sign in and tap the heart on any idea to keep it here.',
            )
          : RefreshIndicator(
              onRefresh: () => ref.refresh(favoritesProvider(null).future),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: favoriteTiles(
                  context,
                  ref,
                  null,
                  empty:
                      'No favourites yet. Tap the heart on an idea you '
                      'want to keep.',
                ),
              ),
            ),
    );
  }
}

/// List entries for a favourites list, with a footer that loads the next
/// page when it scrolls into view.
List<Widget> favoriteTiles(
  BuildContext context,
  WidgetRef ref,
  String? handle, {
  required String empty,
}) {
  final favs = ref.watch(favoritesProvider(handle));
  return favs.when(
    loading: () => const [
      Padding(padding: EdgeInsets.all(32), child: LoadingView()),
    ],
    error: (e, _) => [
      ErrorView(
        error: e,
        onRetry: () => ref.invalidate(favoritesProvider(handle)),
      ),
    ],
    data: (state) {
      if (state.posts.isEmpty) {
        return [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(empty, textAlign: TextAlign.center),
          ),
        ];
      }
      return [
        for (final p in state.posts)
          ReadingWidth(child: CardTile(card: p.card)),
        if (state.loadMoreError != null)
          ErrorView(
            error: state.loadMoreError!,
            onRetry: () =>
                ref.read(favoritesProvider(handle).notifier).loadMore(),
          )
        else if (state.hasMore)
          Builder(
            builder: (context) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  ref.read(favoritesProvider(handle).notifier).loadMore();
                }
              });
              return const Padding(
                padding: EdgeInsets.all(16),
                child: LoadingView(),
              );
            },
          ),
        const SizedBox(height: 24),
      ];
    },
  );
}
