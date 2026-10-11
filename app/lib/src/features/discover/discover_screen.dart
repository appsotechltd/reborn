import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';
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
/// and authors, and book circles.
class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            : [for (final p in posts.take(10)) _PostTile(post: p)],
      ),
      const _Heading('New ideas'),
      if (d.newPosts.isEmpty) const _Empty('No new ideas yet.'),
      for (final p in d.newPosts.take(10)) _PostTile(post: p),
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
  const CircleTile({super.key, required this.circle});
  final Circle circle;

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
      onTap: () => context.push('/circles/${Uri.encodeComponent(circle.id)}'),
    ),
  );
}

class _PostTile extends ConsumerWidget {
  const _PostTile({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = post.stats;
    final activity = s.totalReactions + s.comments + s.favorites;
    return ReadingWidth(
      child: CardTile(
        card: post.card,
        trailing: activity == 0
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.favorite_border, size: 16),
                  const SizedBox(width: 4),
                  Text(compactCount(activity)),
                ],
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
