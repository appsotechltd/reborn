import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../theme.dart';
import '../listen/listen_controller.dart';
import 'library_controller.dart';

/// "1 idea", "12 ideas".
String ideaCount(int n) => '$n ${n == 1 ? 'idea' : 'ideas'}';

/// "1 video", "3 videos".
String videoCount(int n) => '$n ${n == 1 ? 'video' : 'videos'}';

/// A small "3 videos" pill, shown when a book or author has videos.
class VideoCountBadge extends StatelessWidget {
  const VideoCountBadge(this.count, {super.key});
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = Candlelight.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.inset,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.smart_display_outlined, size: 14, color: c.amberText),
          const SizedBox(width: 4),
          Text(
            videoCount(count),
            style: theme.textTheme.labelSmall?.copyWith(color: c.ink2),
          ),
        ],
      ),
    );
  }
}

/// The cards a book or author page shows: all, or only those with a video.
List<IdeaCard> visibleCards(List<IdeaCard> cards, bool videosOnly) => videosOnly
    ? [
        for (final c in cards)
          if (c.explainer != null) c,
      ]
    : cards;

/// Above a book's or author's cards: "Listen to this book" (plays the cards
/// shown, in order, in Listen mode) and the All / Videos switch (hidden when
/// none of the cards has a video).
class CardCollectionBar extends ConsumerWidget {
  const CardCollectionBar({
    super.key,
    required this.page,
    required this.cards,
    required this.listenLabel,
  });

  /// Keys the All / Videos choice, e.g. `source:<id>`.
  final String page;
  final List<IdeaCard> cards;

  /// "Listen to this book" or "Listen to this author".
  final String listenLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videosOnly = ref.watch(videosOnlyProvider(page));
    final videos = cards.where((c) => c.explainer != null).length;
    final shown = visibleCards(cards, videosOnly && videos > 0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            key: const ValueKey('listen-collection'),
            onPressed: shown.isEmpty
                ? null
                : () {
                    ref.read(listenProvider.notifier).startCards(shown);
                    context.push('/listen');
                  },
            icon: const Icon(Icons.headphones_outlined),
            label: Text(listenLabel),
          ),
          if (videos > 0)
            SegmentedButton<bool>(
              key: const ValueKey('cards-filter'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(
                    'All ${cards.length}',
                    key: const ValueKey('cards-filter-all'),
                    semanticsLabel: 'All, ${ideaCount(cards.length)}',
                  ),
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.smart_display_outlined, size: 18),
                  label: Text(
                    'Videos $videos',
                    key: const ValueKey('cards-filter-videos'),
                    semanticsLabel: 'Videos, ${videoCount(videos)}',
                  ),
                ),
              ],
              selected: {videosOnly},
              onSelectionChanged: (s) =>
                  ref.read(videosOnlyProvider(page).notifier).set(s.first),
            ),
        ],
      ),
    );
  }
}

/// The trailing mark on a card with an explainer video.
class HasVideoIcon extends StatelessWidget {
  const HasVideoIcon({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Has a video',
    child: Icon(
      Icons.smart_display_outlined,
      color: Candlelight.of(context).amberText,
    ),
  );
}
