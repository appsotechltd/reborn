import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../circles/circles_screen.dart';
import '../library/card_collection.dart';
import '../library/library_controller.dart';
import '../listen/listen_follow.dart';
import '../post/share.dart';
import '../social/follow_button.dart';
import '../summary/summary_widgets.dart';

const _licenceNames = {
  'public-domain': 'Public domain',
  'us-gov-public-domain': 'US Government work (public domain)',
  'cc-by-4.0': 'CC BY 4.0',
  'cc-by-3.0': 'CC BY 3.0',
  'cc-by-sa-4.0': 'CC BY-SA 4.0',
  'cc0-1.0': 'CC0 1.0',
  'ogl-3.0': 'Open Government Licence v3.0',
  'original-summary': 'Summarised in our own words — read the original',
};

class SourceScreen extends ConsumerWidget {
  const SourceScreen({super.key, required this.sourceId});
  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(sourceProvider(sourceId));
    return Scaffold(
      appBar: AppBar(
        leading: exitLeading(context),
        title: const Text('Source'),
        actions: [
          if (detail.value?.value.source case final s?)
            ShareLinkButton(
              key: const ValueKey('source-share'),
              title: s.authors.isEmpty
                  ? s.title
                  : '${s.title} by ${s.authors.join(', ')}',
              path: '/sources/${Uri.encodeComponent(s.id)}',
            ),
        ],
      ),
      body: detail.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(sourceProvider(sourceId)),
        ),
        data: (f) {
          final cards = f.value.cards;
          final page = 'source:$sourceId';
          final videos = cards.any((c) => c.explainer != null);
          final videosOnly = videos && ref.watch(videosOnlyProvider(page));
          final shown = visibleCards(cards, videosOnly);
          final listen = collectionListenTarget(ref, page, shown, videosOnly);
          final before = [
            ReadingWidth(
              child: _SourceHeader(
                source: f.value.source,
                count: cards.length,
                follow: f.value.follow,
                summaryId: f.value.summaryId,
              ),
            ),
            ReadingWidth(
              child: CardCollectionBar(
                page: page,
                cards: cards,
                listenLabel: 'Listen to this book',
              ),
            ),
          ];
          final after = [
            ReadingWidth(
              child: SourceCircles(
                sourceId: f.value.source.id,
                sourceTitle: f.value.source.title,
              ),
            ),
            const SizedBox(height: 24),
          ];
          return ListenFollow(
            target: listen,
            onMove: (p) => openListenCard(context, p),
            catchUp: false,
            child: ListView.builder(
              itemCount: before.length + shown.length + after.length,
              itemBuilder: (context, i) {
                if (i < before.length) return before[i];
                i -= before.length;
                if (i < shown.length) {
                  final c = shown[i];
                  return ReadingWidth(
                    child: CardTile(
                      key: ValueKey('source-card-${c.id}'),
                      card: c,
                      trailing: c.explainer != null
                          ? const HasVideoIcon()
                          : null,
                    ),
                  );
                }
                return after[i - shown.length];
              },
            ),
          );
        },
      ),
    );
  }
}

class _SourceHeader extends StatelessWidget {
  const _SourceHeader({
    required this.source,
    required this.count,
    required this.follow,
    this.summaryId,
  });
  final Source source;
  final int count;
  final FollowState follow;
  final String? summaryId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            source.kind.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.2),
          ),
          const SizedBox(height: 4),
          Text(source.title, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: [
              for (final a in source.authors)
                InkWell(
                  key: ValueKey('source-author-$a'),
                  borderRadius: BorderRadius.circular(6),
                  onTap: () =>
                      context.push('/authors/${Uri.encodeComponent(a)}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      a,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FollowButton(
            kind: FollowKind.source,
            target: source.id,
            initial: follow,
          ),
          if (summaryId != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('source-summary'),
              onPressed: () => context.push(summaryPath(summaryId!)),
              icon: const Icon(Icons.library_books_outlined, size: 18),
              label: Text(
                source.licence == 'original-summary'
                    ? 'Read the key ideas summary'
                    : 'Read the full summary',
              ),
            ),
          ],
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Licence', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(_licenceNames[source.licence] ?? source.licence),
                  const SizedBox(height: 8),
                  Text(source.attribution, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (source.url.isNotEmpty)
                        FilledButton.tonalIcon(
                          onPressed: () => openExternal(context, source.url),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('Open source'),
                        ),
                      if (source.licenceUrl != null &&
                          source.licenceUrl!.isNotEmpty)
                        TextButton(
                          onPressed: () =>
                              openExternal(context, source.licenceUrl!),
                          child: const Text('Licence terms'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '$count ${count == 1 ? 'idea' : 'ideas'} from this source',
            style: theme.textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
