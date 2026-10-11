import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../data/providers.dart';

/// Local copies of posts the user acted on, so every view of a post
/// (timeline, card screen, favourites) shows the same optimistic state.
///
/// Lists keep the server's copy; widgets show `store[id] ?? serverCopy`
/// (see [watchPost]). Cleared on sign-in/out and when the timeline refreshes.
class PostStore extends Notifier<Map<String, Post>> {
  @override
  Map<String, Post> build() {
    ref.watch(sessionProvider.select((s) => s.token));
    return const {};
  }

  /// The newest local copy of [post].
  Post current(Post post) => state[post.id] ?? post;

  void put(Post post) => state = {...state, post.id: post};

  void forget() {
    if (state.isNotEmpty) state = const {};
  }

  /// Sets [kind], or clears it when it is already the viewer's reaction.
  Future<void> react(Post post, Reaction kind) async {
    final before = current(post);
    final next = before.myReaction == kind ? null : kind;
    put(before.withReaction(next));
    try {
      await ref.read(repositoryProvider).setReaction(post.id, next);
    } catch (_) {
      put(before);
      rethrow;
    }
  }

  Future<void> toggleFavorite(Post post) async {
    final before = current(post);
    final on = !before.favorited;
    put(before.withFavorite(on));
    try {
      await ref.read(repositoryProvider).setFavorite(post.id, on);
    } catch (_) {
      put(before);
      rethrow;
    }
  }

  void countShare(Post post) {
    final p = current(post);
    put(p.copyWith(stats: p.stats.copyWith(shares: p.stats.shares + 1)));
  }

  void countGift(Post post) {
    final p = current(post);
    put(p.copyWith(stats: p.stats.copyWith(gifts: p.stats.gifts + 1)));
  }

  /// Adjusts the comment count of post [id] when a copy of it is known.
  void countComments(String id, int delta, {Post? base}) {
    final p = state[id] ?? base;
    if (p == null) return;
    final n = p.stats.comments + delta;
    put(p.copyWith(stats: p.stats.copyWith(comments: n < 0 ? 0 : n)));
  }
}

final postStoreProvider = NotifierProvider<PostStore, Map<String, Post>>(
  PostStore.new,
);

/// Watches the newest local copy of [post].
Post watchPost(WidgetRef ref, Post post) =>
    ref.watch(postStoreProvider.select((m) => m[post.id])) ?? post;
