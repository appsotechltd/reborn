import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../library/card_collection.dart';
import '../library/library_controller.dart';
import '../listen/listen_follow.dart';
import 'follow_button.dart';

/// An author: their sources in the library, a follow button, and every
/// idea from their work (all, or only those with a video), which Listen
/// mode can play in order.
class AuthorScreen extends ConsumerWidget {
  const AuthorScreen({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final author = ref.watch(authorProvider(name));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: exitLeading(context),
        title: const Text('Author'),
      ),
      body: author.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(authorProvider(name)),
        ),
        data: (a) {
          final page = 'author:$name';
          final videos = a.cards.any((c) => c.explainer != null);
          final videosOnly = videos && ref.watch(videosOnlyProvider(page));
          final shown = visibleCards(a.cards, videosOnly);
          final listen = collectionListenTarget(ref, page, shown, videosOnly);
          final before = <Widget>[
            ReadingWidth(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AUTHOR',
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(a.name, style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 12),
                    FollowButton(
                      kind: FollowKind.author,
                      target: a.name,
                      initial: a.follow,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Follow to see new ideas from their work in your '
                      'timeline.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${a.sources.length} '
                      '${a.sources.length == 1 ? 'source' : 'sources'} '
                      'in the library',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
            for (final s in a.sources)
              ReadingWidth(
                child: ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(s.title),
                  subtitle: Text(
                    '${s.cardCount} ${s.cardCount == 1 ? 'idea' : 'ideas'}'
                    '${s.videoCount > 0 ? ' · ${videoCount(s.videoCount)}' : ''}'
                    '${s.kind.isEmpty ? '' : ' · ${s.kind}'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      context.push('/sources/${Uri.encodeComponent(s.id)}'),
                ),
              ),
            if (a.cards.isNotEmpty) ...[
              ReadingWidth(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                  child: Text(
                    'All ${ideaCount(a.cards.length)} by ${a.name}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
              ReadingWidth(
                child: CardCollectionBar(
                  page: page,
                  cards: a.cards,
                  listenLabel: 'Listen to this author',
                ),
              ),
            ],
          ];
          return ListenFollow(
            target: listen,
            child: ListView.builder(
              itemCount: before.length + shown.length + 1,
              itemBuilder: (context, i) {
                if (i < before.length) return before[i];
                i -= before.length;
                if (i == shown.length) return const SizedBox(height: 24);
                final c = shown[i];
                return ReadingWidth(
                  child: CardTile(
                    key: ValueKey('author-card-${c.id}'),
                    card: c,
                    trailing: c.explainer != null ? const HasVideoIcon() : null,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
