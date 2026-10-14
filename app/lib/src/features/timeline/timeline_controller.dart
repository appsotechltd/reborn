import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../data/providers.dart';

/// Selected topic chip on the timeline; null means "For you".
class TimelineFilter extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? topic) => state = topic;
}

final timelineFilterProvider = NotifierProvider<TimelineFilter, String?>(
  TimelineFilter.new,
);

class TimelineState {
  const TimelineState({
    required this.posts,
    this.nextCursor,
    this.loadingMore = false,
    this.offline = false,
    this.loadMoreError,
  });

  final List<Post> posts;
  final String? nextCursor;
  final bool loadingMore;
  final bool offline;
  final Object? loadMoreError;

  bool get hasMore => nextCursor != null;

  /// Where "You're all caught up" goes; see [caughtUpIndex].
  int? get caughtUp => caughtUpIndex(posts);

  TimelineState copyWith({
    List<Post>? posts,
    String? nextCursor,
    bool clearCursor = false,
    bool? loadingMore,
    bool? offline,
    Object? loadMoreError,
  }) => TimelineState(
    posts: posts ?? this.posts,
    nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
    loadingMore: loadingMore ?? this.loadingMore,
    offline: offline ?? this.offline,
    loadMoreError: loadMoreError,
  );
}

/// The index of the first already-seen post that follows the unseen ones
/// (the timeline lists unseen posts first). Null when signed out (no
/// `viewer`) or when every post is unseen.
int? caughtUpIndex(List<Post> posts) {
  for (var i = 0; i < posts.length; i++) {
    if (posts[i].isSummary) continue;
    final v = posts[i].viewer;
    if (v == null) return null;
    if (v.seen) return i;
  }
  return null;
}

class TimelineController extends AsyncNotifier<TimelineState> {
  List<String>? _topics;

  /// The topics the timeline was fetched with (null: the server's choice);
  /// Listen mode loads further pages with the same filter.
  List<String>? get topics => _topics;

  @override
  Future<TimelineState> build() async {
    final filter = ref.watch(timelineFilterProvider);
    final signedIn = ref.watch(sessionProvider.select((s) => s.signedIn));
    final prefs = ref.watch(topicPrefsProvider);
    // Signed in, "For you" omits `topics` so the server uses the account's
    // topics and follows.
    _topics = filter != null
        ? [filter]
        : (signedIn ? null : (prefs.isEmpty ? null : prefs));
    final page = await ref
        .read(repositoryProvider)
        .timeline(topics: _topics, withSummaries: true);
    return TimelineState(
      posts: page.value.posts,
      nextCursor: page.value.nextCursor,
      offline: page.offline,
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref
          .read(repositoryProvider)
          .timeline(
            topics: _topics,
            cursor: current.nextCursor,
            withSummaries: true,
          );
      final have = current.posts.map((p) => p.id).toSet();
      state = AsyncData(
        current.copyWith(
          posts: [
            ...current.posts,
            ...page.value.posts.where((p) => !have.contains(p.id)),
          ],
          nextCursor: page.value.nextCursor,
          clearCursor: page.value.nextCursor == null,
          loadingMore: false,
          offline: page.offline,
        ),
      );
    } catch (e) {
      state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: e));
    }
  }
}

final timelineProvider =
    AsyncNotifierProvider<TimelineController, TimelineState>(
      TimelineController.new,
    );
