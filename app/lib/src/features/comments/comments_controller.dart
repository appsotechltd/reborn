import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../data/providers.dart';

class CommentsState {
  const CommentsState({
    required this.comments,
    this.nextCursor,
    this.loadingMore = false,
  });

  /// Oldest first, as the API sends them.
  final List<Comment> comments;
  final String? nextCursor;
  final bool loadingMore;

  bool get hasMore => nextCursor != null;
  List<CommentThread> get threads => threadComments(comments);

  CommentsState copyWith({
    List<Comment>? comments,
    String? nextCursor,
    bool clearCursor = false,
    bool? loadingMore,
  }) => CommentsState(
    comments: comments ?? this.comments,
    nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// Comments of one post.
class CommentsController extends AsyncNotifier<CommentsState> {
  CommentsController(this.postId);
  final String postId;

  @override
  Future<CommentsState> build() async {
    final page = await ref.read(repositoryProvider).comments(postId);
    return CommentsState(comments: page.comments, nextCursor: page.nextCursor);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref
          .read(repositoryProvider)
          .comments(postId, cursor: current.nextCursor);
      final have = current.comments.map((c) => c.id).toSet();
      state = AsyncData(
        current.copyWith(
          comments: [
            ...current.comments,
            ...page.comments.where((c) => !have.contains(c.id)),
          ],
          nextCursor: page.nextCursor,
          clearCursor: page.nextCursor == null,
          loadingMore: false,
        ),
      );
    } catch (_) {
      state = AsyncData(current.copyWith(loadingMore: false));
      rethrow;
    }
  }

  /// Posts a comment (or a reply to [parentId]) and appends it.
  Future<Comment> add(String body, {String? parentId}) async {
    final c = await ref
        .read(repositoryProvider)
        .addComment(postId, body, parentId: parentId);
    final current = state.value ?? const CommentsState(comments: []);
    state = AsyncData(current.copyWith(comments: [...current.comments, c]));
    return c;
  }

  /// Deletes a comment; returns how many comments disappeared (with replies).
  Future<int> delete(String id) async {
    await ref.read(repositoryProvider).deleteComment(id);
    final current = state.value;
    if (current == null) return 1;
    final kept = current.comments
        .where((c) => c.id != id && c.parentId != id)
        .toList();
    state = AsyncData(current.copyWith(comments: kept));
    return current.comments.length - kept.length;
  }

  Future<void> report(String id, {String? reason}) =>
      ref.read(repositoryProvider).reportComment(id, reason: reason);
}

final commentsProvider = AsyncNotifierProvider.autoDispose
    .family<CommentsController, CommentsState, String>(CommentsController.new);
