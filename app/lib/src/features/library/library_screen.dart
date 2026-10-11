import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../layout/adaptive.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../social/author_screen.dart';
import '../source/source_screen.dart';
import 'card_collection.dart';
import 'library_controller.dart';

/// Load the next page when the list is this many rows from its end.
const kLibraryPreloadRemaining = 5;

/// How long typing pauses before the Library searches.
const kLibrarySearchDebounce = Duration(milliseconds: 300);

/// A book or author picked in the Library, shown on the right on expanded
/// windows.
typedef LibraryPick = ({String kind, String id});

/// The Library: every book and every author, searchable and filtered by
/// topic, a page at a time. A book or author opens its page with all its
/// ideas; on expanded windows it opens on the right.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, this.initialTab = 0});

  /// 0: Books, 1: Authors.
  final int initialTab;

  static const pane = 'library';

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.initialTab.clamp(0, 1),
  );
  final _search = TextEditingController();
  Timer? _debounce;
  String _q = '';
  String? _topic;

  LibraryQuery get _query => (q: _q, topic: _topic);

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(kLibrarySearchDebounce, () {
      if (!mounted) return;
      final q = text.trim();
      if (q != _q) setState(() => _q = q);
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _search.clear();
    setState(() => _q = '');
  }

  @override
  Widget build(BuildContext context) {
    final picked = ref.watch(paneSelectionProvider(LibraryScreen.pane));
    final pick = picked is LibraryPick ? picked : null;
    return ListDetail(
      list: _list(context),
      selectedId: pick == null ? null : '${pick.kind}:${pick.id}',
      detail: () => pick!.kind == 'author'
          ? AuthorScreen(name: pick.id)
          : SourceScreen(sourceId: pick.id),
      empty: const EmptyDetail(
        icon: Icons.local_library_outlined,
        text: 'Pick a book or an author to see all its ideas here.',
      ),
    );
  }

  Widget _list(BuildContext context) {
    final topics = ref.watch(topicsProvider).value ?? kDefaultTopics;
    return Scaffold(
      appBar: AppBar(
        leading: exitLeading(context),
        title: const Text('Library'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(key: ValueKey('library-tab-books'), text: 'Books'),
            Tab(key: ValueKey('library-tab-authors'), text: 'Authors'),
          ],
        ),
      ),
      body: Column(
        children: [
          ReadingWidth(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: ListenableBuilder(
                listenable: _search,
                builder: (context, _) => TextField(
                  key: const ValueKey('library-search'),
                  controller: _search,
                  onChanged: _onSearch,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search books and authors',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            key: const ValueKey('library-search-clear'),
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close),
                            onPressed: _clearSearch,
                          ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              key: const ValueKey('library-topics'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    key: const ValueKey('library-topic-all'),
                    label: const Text('All topics'),
                    selected: _topic == null,
                    onSelected: (_) => setState(() => _topic = null),
                  ),
                ),
                for (final t in topics)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      key: ValueKey('library-topic-${t.slug}'),
                      label: Text(t.name),
                      selected: _topic == t.slug,
                      onSelected: (on) =>
                          setState(() => _topic = on ? t.slug : null),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _BooksList(query: _query),
                _AuthorsList(query: _query),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens a book or author: on the right on expanded windows, else its page.
void _open(BuildContext context, WidgetRef ref, LibraryPick pick) {
  if (WindowSize.of(context).isTwoPane) {
    ref.read(paneSelectionProvider(LibraryScreen.pane).notifier).select(pick);
    return;
  }
  context.push(
    pick.kind == 'author'
        ? '/authors/${Uri.encodeComponent(pick.id)}'
        : '/sources/${Uri.encodeComponent(pick.id)}',
  );
}

bool _isPicked(BuildContext context, WidgetRef ref, LibraryPick pick) {
  if (!WindowSize.of(context).isTwoPane) return false;
  final picked = ref.watch(paneSelectionProvider(LibraryScreen.pane));
  return picked is LibraryPick && picked == pick;
}

class _BooksList extends ConsumerWidget {
  const _BooksList({required this.query});
  final LibraryQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _PagedList<SourceSummary>(
        listKey: const ValueKey('library-books'),
        value: ref.watch(libraryBooksProvider(query)),
        onRetry: () => ref.invalidate(libraryBooksProvider(query)),
        onLoadMore: () =>
            ref.read(libraryBooksProvider(query).notifier).loadMore(),
        empty: query.q.isEmpty && query.topic == null
            ? 'No books yet.'
            : 'No books match.',
        itemBuilder: (context, s) => _BookRow(source: s),
      );
}

class _AuthorsList extends ConsumerWidget {
  const _AuthorsList({required this.query});
  final LibraryQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _PagedList<AuthorSummary>(
        listKey: const ValueKey('library-authors'),
        value: ref.watch(libraryAuthorsProvider(query)),
        onRetry: () => ref.invalidate(libraryAuthorsProvider(query)),
        onLoadMore: () =>
            ref.read(libraryAuthorsProvider(query).notifier).loadMore(),
        empty: query.q.isEmpty && query.topic == null
            ? 'No authors yet.'
            : 'No authors match.',
        itemBuilder: (context, a) => _AuthorRow(author: a),
      );
}

/// A list loaded a page at a time: the next page loads as the reader nears
/// the end; a failed page shows "Try again".
class _PagedList<T> extends StatelessWidget {
  const _PagedList({
    required this.listKey,
    required this.value,
    required this.onRetry,
    required this.onLoadMore,
    required this.empty,
    required this.itemBuilder,
  });

  final Key listKey;
  final AsyncValue<LibraryList<T>> value;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;
  final String empty;
  final Widget Function(BuildContext context, T item) itemBuilder;

  @override
  Widget build(BuildContext context) => value.when(
    skipLoadingOnReload: true,
    loading: () => const LoadingView(),
    error: (e, _) => ErrorView(error: e, onRetry: onRetry),
    data: (list) {
      if (list.items.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(empty, textAlign: TextAlign.center),
          ),
        );
      }
      final footer = list.hasMore || list.loadMoreError != null;
      return ListView.builder(
        key: listKey,
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: list.items.length + (footer ? 1 : 0),
        itemBuilder: (context, i) {
          if (i < list.items.length) {
            if (list.hasMore &&
                !list.loadingMore &&
                list.loadMoreError == null &&
                list.items.length - 1 - i <= kLibraryPreloadRemaining) {
              WidgetsBinding.instance.addPostFrameCallback((_) => onLoadMore());
            }
            return ReadingWidth(child: itemBuilder(context, list.items[i]));
          }
          if (list.loadMoreError != null) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: OutlinedButton(
                  key: const ValueKey('library-more-retry'),
                  onPressed: onLoadMore,
                  child: const Text('Try again'),
                ),
              ),
            );
          }
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        },
      );
    },
  );
}

/// The small line of counts under a book or author.
class _Counts extends StatelessWidget {
  const _Counts({required this.parts, required this.videos});
  final List<String> parts;
  final int videos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = Candlelight.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            parts.join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(color: c.muted),
          ),
          if (videos > 0) VideoCountBadge(videos),
        ],
      ),
    );
  }
}

class _BookRow extends ConsumerWidget {
  const _BookRow({required this.source});
  final SourceSummary source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(topicNamesProvider);
    final pick = (kind: 'book', id: source.id);
    final topics = [for (final t in source.topics) names[t] ?? t];
    return ListTile(
      key: ValueKey('library-book-${source.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.menu_book_outlined),
      title: Text(source.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (source.authors.isNotEmpty)
            Text(
              source.authors.join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          _Counts(
            parts: [ideaCount(source.cardCount)],
            videos: source.videoCount,
          ),
          if (topics.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: CategoryTag(topics.join(' · ')),
            ),
        ],
      ),
      selected: _isPicked(context, ref, pick),
      onTap: () => _open(context, ref, pick),
    );
  }
}

class _AuthorRow extends ConsumerWidget {
  const _AuthorRow({required this.author});
  final AuthorSummary author;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = author;
    final pick = (kind: 'author', id: a.name);
    return ListTile(
      key: ValueKey('library-author-${a.name}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(Icons.history_edu_outlined),
      title: Text(a.name),
      subtitle: _Counts(
        parts: [
          '${a.sources} ${a.sources == 1 ? 'book' : 'books'}',
          ideaCount(a.cardCount),
        ],
        videos: a.videoCount,
      ),
      selected: _isPicked(context, ref, pick),
      onTap: () => _open(context, ref, pick),
    );
  }
}
