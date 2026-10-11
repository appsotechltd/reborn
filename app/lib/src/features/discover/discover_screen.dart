import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../layout/adaptive.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../card/card_screen.dart';
import '../notifications/notifications_screen.dart';

/// Selected topic for Trending on Discover; null means all topics.
class TrendingTopic extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? topic) => state = topic;
}

final trendingTopicProvider = NotifierProvider<TrendingTopic, String?>(
  TrendingTopic.new,
);

/// The Discover tab: search, trending (by topic), new posts, popular books
/// and authors, and book circles. On expanded windows an idea picked from
/// the list opens on the right.
class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  static const pane = 'discover';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(paneSelectionProvider(pane));
    final card = selected is IdeaCard ? selected : null;
    return ListDetail(
      list: _list(context, ref),
      selectedId: card?.id,
      detail: () => CardScreen(cardId: card!.id, initial: card),
      empty: const EmptyDetail(
        icon: Icons.auto_stories_outlined,
        text: 'Pick an idea to read it here.',
      ),
    );
  }

  Widget _list(BuildContext context, WidgetRef ref) {
    final discover = ref.watch(discoverProvider);
    final topic = ref.watch(trendingTopicProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: const [
          NotificationBell(),
          ProfileMenuButton(),
          SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (topic != null) ref.invalidate(trendingProvider(topic));
          final _ = await ref.refresh(discoverProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            ReadingWidth(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: SearchBar(
                  key: const ValueKey('discover-search'),
                  hintText: 'Search ideas',
                  leading: const Icon(Icons.search),
                  elevation: const WidgetStatePropertyAll(0),
                  onTap: () => context.push('/search'),
                  readOnly: true,
                ),
              ),
            ),
            ...discover.when(
              loading: () => const [
                Padding(padding: EdgeInsets.all(48), child: LoadingView()),
              ],
              error: (e, _) => [
                ErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(discoverProvider),
                ),
              ],
              data: (d) => _sections(context, ref, d, topic),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  List<Widget> _sections(
    BuildContext context,
    WidgetRef ref,
    DiscoverPage d,
    String? topic,
  ) {
    final trending = topic == null
        ? AsyncValue.data(d.trending)
        : ref.watch(trendingProvider(topic));
    return [
      const _Heading('Trending this week'),
      const _TopicFilter(),
      ...trending.when(
        loading: () => const [
          Padding(padding: EdgeInsets.all(24), child: LoadingView()),
        ],
        error: (e, _) => [
          ErrorView(
            error: e,
            onRetry: () => ref.invalidate(trendingProvider(topic ?? '')),
          ),
        ],
        data: (posts) => posts.isEmpty
            ? const [_Empty('Nothing trending here yet.')]
            : [
                for (final (i, p) in posts.take(10).indexed)
                  DiscoverPostCard(post: p, rank: i + 1),
              ],
      ),
      const _Heading('New ideas'),
      if (d.newPosts.isEmpty) const _Empty('No new ideas yet.'),
      for (final p in d.newPosts.take(6)) DiscoverPostCard(post: p),
      if (d.books.isNotEmpty) ...[
        const _Heading('Popular books'),
        SizedBox(
          height: 128,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [for (final b in d.books) _BookCard(book: b)],
          ),
        ),
      ],
      if (d.authors.isNotEmpty) ...[
        const _Heading('Popular authors'),
        for (final a in d.authors)
          ReadingWidth(
            child: ListTile(
              leading: const Icon(Icons.history_edu_outlined),
              title: Text(a.name),
              subtitle: Text(
                '${compactCount(a.followers)} '
                '${a.followers == 1 ? 'follower' : 'followers'} · '
                '${a.sources} ${a.sources == 1 ? 'book' : 'books'}',
              ),
              onTap: () =>
                  context.push('/authors/${Uri.encodeComponent(a.name)}'),
            ),
          ),
      ],
      _Heading(
        'Book circles',
        action: TextButton(
          onPressed: () => context.push('/circles'),
          child: const Text('All circles'),
        ),
      ),
      if (d.circles.isEmpty)
        const _Empty('No circles yet. Start one from any book page.'),
      for (final c in d.circles) CircleTile(circle: c),
    ];
  }
}

/// A circle in a list; opens the circle screen.
class CircleTile extends StatelessWidget {
  const CircleTile({
    super.key,
    required this.circle,
    this.onTap,
    this.selected = false,
  });
  final Circle circle;

  /// Instead of opening the circle screen (e.g. to show it in a side pane).
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => ReadingWidth(
    child: ListTile(
      key: ValueKey('circle-${circle.id}'),
      leading: const Icon(Icons.groups_outlined),
      title: Text(circle.name),
      subtitle: Text(
        '${circle.sourceTitle} · ${circle.members} '
        '${circle.members == 1 ? 'member' : 'members'}',
      ),
      trailing: circle.isMember ? const Icon(Icons.check, size: 18) : null,
      selected: selected,
      onTap:
          onTap ??
          () => context.push('/circles/${Uri.encodeComponent(circle.id)}'),
    ),
  );
}

/// "The first 130 characters…", cut at a word: the excerpt on a post card.
String excerpt(String text, [int max = 130]) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (flat.length <= max) return flat;
  final cut = flat.substring(0, max - 1);
  final space = cut.lastIndexOf(' ');
  return '${space > 80 ? cut.substring(0, space) : cut}…';
}

/// A post in a Discover list: topic, title, excerpt, credit and how people
/// responded, with its rank in Trending. Opens the card screen, or on
/// expanded windows shows the card on the right.
class DiscoverPostCard extends ConsumerWidget {
  const DiscoverPostCard({super.key, required this.post, this.rank});
  final Post post;
  final int? rank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = Candlelight.of(context);
    final card = post.card;
    final s = post.stats;
    final topicName = ref.watch(topicNamesProvider)[card.topic] ?? card.topic;
    final twoPane = WindowSize.of(context).isTwoPane;
    final picked = ref.watch(paneSelectionProvider(DiscoverScreen.pane));
    final selected = twoPane && picked is IdeaCard && picked.id == card.id;
    final muted = theme.textTheme.bodySmall;
    String count(int n, String one, String many) =>
        '${compactCount(n)} ${n == 1 ? one : many}';
    return ReadingWidth(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Card(
          key: ValueKey('discover-post-${post.id}'),
          shape: selected
              ? RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    CandlelightTokens.radiusCard,
                  ),
                  side: BorderSide(color: c.amberText, width: 1.5),
                )
              : null,
          child: InkWell(
            onTap: twoPane
                ? () => ref
                      .read(paneSelectionProvider(DiscoverScreen.pane).notifier)
                      .select(card)
                : () => context.push(
                    '/cards/${Uri.encodeComponent(card.id)}',
                    extra: card,
                  ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (rank != null)
                    ExcludeSemantics(
                      child: SizedBox(
                        width: 34,
                        child: Text(
                          '$rank',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: c.muted,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CategoryTag(topicName),
                        const SizedBox(height: 4),
                        Text(
                          card.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 20,
                            height: 1.3,
                          ),
                        ),
                        if (card.body.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            excerpt(card.body),
                            key: const ValueKey('discover-excerpt'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: c.muted,
                              height: 1.55,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(card.credit, style: muted?.copyWith(fontSize: 12)),
                        const SizedBox(height: 6),
                        Text(
                          [
                            count(s.totalReactions, 'reaction', 'reactions'),
                            count(s.comments, 'comment', 'comments'),
                            count(s.favorites, 'favourite', 'favourites'),
                          ].join('   '),
                          key: const ValueKey('discover-counts'),
                          style: muted?.copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({required this.book});
  final PopularBook book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = book.source;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        width: 180,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push('/sources/${Uri.encodeComponent(s.id)}'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.menu_book_outlined, size: 20),
                  const SizedBox(height: 6),
                  Text(
                    s.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    s.authors.join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  const Spacer(),
                  Text(
                    '${compactCount(book.followers)} followers',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopicFilter extends ConsumerWidget {
  const _TopicFilter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topics = ref.watch(topicsProvider).value ?? kDefaultTopics;
    final selected = ref.watch(trendingTopicProvider);
    final notifier = ref.read(trendingTopicProvider.notifier);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: const Text('All topics'),
              selected: selected == null,
              onSelected: (_) => notifier.select(null),
            ),
          ),
          for (final t in topics)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(t.name),
                selected: selected == t.slug,
                onSelected: (on) => notifier.select(on ? t.slug : null),
              ),
            ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => ReadingWidth(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.titleMedium),
          ),
          ?action,
        ],
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => ReadingWidth(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    ),
  );
}
