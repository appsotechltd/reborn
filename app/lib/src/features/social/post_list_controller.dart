import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../data/providers.dart';

class PostListState {
  const PostListState({
    required this.posts,
    this.nextCursor,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<Post> posts;
  final String? nextCursor;
  final bool loadingMore;
  final Object? loadMoreError;

  bool get hasMore => nextCursor != null;
}

/// A paged list of favourites: the signed-in user's when [handle] is null,
/// otherwise that user's.
class FavoritesController extends AsyncNotifier<PostListState> {
  FavoritesController(this.handle);
  final String? handle;

  Future<PostPage> _page(String? cursor) {
    final repo = ref.read(repositoryProvider);
    return handle == null
        ? repo.myFavorites(cursor: cursor)
        : repo.userFavorites(handle!, cursor: cursor);
  }

  @override
  Future<PostListState> build() async {
    ref.watch(sessionProvider.select((s) => s.token));
    final page = await _page(null);
    return PostListState(posts: page.posts, nextCursor: page.nextCursor);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(
      PostListState(
        posts: current.posts,
        nextCursor: current.nextCursor,
        loadingMore: true,
      ),
    );
    try {
      final page = await _page(current.nextCursor);
      final have = current.posts.map((p) => p.id).toSet();
      state = AsyncData(
        PostListState(
          posts: [
            ...current.posts,
            ...page.posts.where((p) => !have.contains(p.id)),
          ],
          nextCursor: page.nextCursor,
        ),
      );
    } catch (e) {
      state = AsyncData(
        PostListState(
          posts: current.posts,
          nextCursor: current.nextCursor,
          loadMoreError: e,
        ),
      );
    }
  }
}

final favoritesProvider = AsyncNotifierProvider.autoDispose
    .family<FavoritesController, PostListState, String?>(
      FavoritesController.new,
    );
