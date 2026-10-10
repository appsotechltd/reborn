import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../data/providers.dart';

/// Selected topic filter chip on Home; null means "For you".
class FeedFilter extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? topic) => state = topic;
}

final feedFilterProvider = NotifierProvider<FeedFilter, String?>(
  FeedFilter.new,
);

class FeedState {
  const FeedState({
    required this.cards,
    this.nextCursor,
    this.loadingMore = false,
    this.offline = false,
    this.loadMoreError,
  });

  final List<IdeaCard> cards;
  final String? nextCursor;
  final bool loadingMore;
  final bool offline;
  final Object? loadMoreError;

  bool get hasMore => nextCursor != null;

  FeedState copyWith({
    List<IdeaCard>? cards,
    String? nextCursor,
    bool clearCursor = false,
    bool? loadingMore,
    bool? offline,
    Object? loadMoreError,
  }) => FeedState(
    cards: cards ?? this.cards,
    nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
    loadingMore: loadingMore ?? this.loadingMore,
    offline: offline ?? this.offline,
    loadMoreError: loadMoreError,
  );
}

class FeedController extends AsyncNotifier<FeedState> {
  List<String>? _topics;

  @override
  Future<FeedState> build() async {
    final filter = ref.watch(feedFilterProvider);
    final signedIn = ref.watch(sessionProvider.select((s) => s.signedIn));
    final prefs = ref.watch(topicPrefsProvider);
    // Signed in, "For you" omits `topics` so the server uses the account's.
    _topics = filter != null
        ? [filter]
        : (signedIn ? null : (prefs.isEmpty ? null : prefs));
    final page = await ref.read(repositoryProvider).feed(topics: _topics);
    return FeedState(
      cards: page.value.cards,
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
          .feed(topics: _topics, cursor: current.nextCursor);
      final seen = current.cards.map((c) => c.id).toSet();
      state = AsyncData(
        current.copyWith(
          cards: [
            ...current.cards,
            ...page.value.cards.where((c) => !seen.contains(c.id)),
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

final feedProvider = AsyncNotifierProvider<FeedController, FeedState>(
  FeedController.new,
);
