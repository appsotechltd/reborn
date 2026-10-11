import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../data/providers.dart';

/// What the Library lists: [q] searches titles and author names, [topic]
/// keeps one topic (null: all).
typedef LibraryQuery = ({String q, String? topic});

/// A list from the library loaded a page at a time.
class LibraryList<T> {
  const LibraryList({
    required this.items,
    this.nextCursor,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<T> items;
  final String? nextCursor;
  final bool loadingMore;
  final Object? loadMoreError;

  bool get hasMore => nextCursor != null;
}

/// Pages through one of the library's lists for a [LibraryQuery].
abstract class _PagedController<T> extends AsyncNotifier<LibraryList<T>> {
  _PagedController(this.query);
  final LibraryQuery query;

  Future<(List<T>, String?)> fetch(String? cursor);

  String keyOf(T item);

  @override
  Future<LibraryList<T>> build() async {
    final (items, next) = await fetch(null);
    return LibraryList(items: items, nextCursor: next);
  }

  /// Loads the next page; a failure is kept for a "Try again".
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(
      LibraryList(
        items: current.items,
        nextCursor: current.nextCursor,
        loadingMore: true,
      ),
    );
    try {
      final (items, next) = await fetch(current.nextCursor);
      final have = current.items.map(keyOf).toSet();
      state = AsyncData(
        LibraryList(
          items: [
            ...current.items,
            ...items.where((i) => !have.contains(keyOf(i))),
          ],
          nextCursor: next,
        ),
      );
    } catch (e) {
      state = AsyncData(
        LibraryList(
          items: current.items,
          nextCursor: current.nextCursor,
          loadMoreError: e,
        ),
      );
    }
  }
}

class LibraryBooksController extends _PagedController<SourceSummary> {
  LibraryBooksController(super.query);

  @override
  Future<(List<SourceSummary>, String?)> fetch(String? cursor) async {
    final page = await ref
        .read(repositoryProvider)
        .sources(
          topic: query.topic,
          q: query.q.isEmpty ? null : query.q,
          cursor: cursor,
        );
    return (page.sources, page.nextCursor);
  }

  @override
  String keyOf(SourceSummary item) => item.id;
}

class LibraryAuthorsController extends _PagedController<AuthorSummary> {
  LibraryAuthorsController(super.query);

  @override
  Future<(List<AuthorSummary>, String?)> fetch(String? cursor) async {
    final page = await ref
        .read(repositoryProvider)
        .authors(
          topic: query.topic,
          q: query.q.isEmpty ? null : query.q,
          cursor: cursor,
        );
    return (page.authors, page.nextCursor);
  }

  @override
  String keyOf(AuthorSummary item) => item.name;
}

final libraryBooksProvider = AsyncNotifierProvider.autoDispose
    .family<LibraryBooksController, LibraryList<SourceSummary>, LibraryQuery>(
      LibraryBooksController.new,
    );

final libraryAuthorsProvider = AsyncNotifierProvider.autoDispose
    .family<LibraryAuthorsController, LibraryList<AuthorSummary>, LibraryQuery>(
      LibraryAuthorsController.new,
    );

/// Whether a book's or author's page shows only the cards with a video,
/// keyed by page (e.g. `source:<id>`, `author:<name>`).
class VideosOnly extends Notifier<bool> {
  VideosOnly(this.page);
  final String page;

  @override
  bool build() => false;

  void set(bool on) => state = on;
}

final videosOnlyProvider = NotifierProvider.autoDispose
    .family<VideosOnly, bool, String>(VideosOnly.new);
