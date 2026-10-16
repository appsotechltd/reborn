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

/// "1 image", "3 images".
String imageCount(int n) => '$n ${n == 1 ? 'image' : 'images'}';

/// The filter a book's or author's page applies: the one [chosen], or All
/// when none of its [cards] has that kind of media (its option is hidden).
MediaFilter collectionFilter(List<IdeaCard> cards, MediaFilter chosen) =>
    chosen == MediaFilter.all || cards.any(chosen.matches)
    ? chosen
    : MediaFilter.all;

/// The cards a book or author page shows: all, or only those with a video,
/// or only those with a picture.
List<IdeaCard> visibleCards(List<IdeaCard> cards, MediaFilter filter) =>
    filter == MediaFilter.all ? cards : cards.where(filter.matches).toList();

/// Names a book's or author's list for Listen mode: `source:<id>|all`,
/// `author:<name>|videos`, `source:<id>|images`.
String collectionListenKey(String page, MediaFilter filter) =>
    '$page|${filter.name}';

/// What a book's or author's [page] plays, for Listen mode to follow (see
/// ListenFollow): the cards [shown]. Null while Listen mode is already on
/// this page's list (All, Videos or Images), so it carries on undisturbed.
ListenTarget? collectionListenTarget(
  WidgetRef ref,
  String page,
  List<IdeaCard> shown,
  MediaFilter filter,
) {
  final ours = ref.watch(
    listenProvider.select((s) => s.queueKey?.startsWith('$page|') ?? false),
  );
  if (ours || shown.isEmpty) return null;
  return ListenTarget.cards(
    key: collectionListenKey(page, filter),
    cards: shown,
  );
}

/// The audio moved on to [post] while a book's or author's page is on
/// show: its card opens (and, from there, the card page keeps up).
void openListenCard(BuildContext context, Post post) => context.push(
  '/cards/${Uri.encodeComponent(post.card.id)}',
  extra: post.card,
);

/// Above a book's or author's cards: "Listen to this book" (plays the cards
/// shown, in order, in Listen mode) and the All / Videos / Images switch.
/// Videos is hidden when none of the cards has a video, Images when none has
/// a picture, and the switch when both are.
class CardCollectionBar extends ConsumerWidget {
  const CardCollectionBar({
    super.key,
    required this.page,
    required this.cards,
    required this.listenLabel,
  });

  /// Keys the All / Videos / Images choice, e.g. `source:<id>`.
  final String page;
  final List<IdeaCard> cards;

  /// "Listen to this book" or "Listen to this author".
  final String listenLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = collectionFilter(
      cards,
      ref.watch(cardsFilterProvider(page)),
    );
    final videos = cards.where(MediaFilter.videos.matches).length;
    final images = cards.where(MediaFilter.images.matches).length;
    final shown = visibleCards(cards, filter);
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
                    ref
                        .read(listenProvider.notifier)
                        .startCards(
                          shown,
                          key: collectionListenKey(page, filter),
                        );
                    context.push('/listen');
                  },
            icon: const Icon(Icons.headphones_outlined),
            label: Text(listenLabel),
          ),
          if (videos > 0 || images > 0)
            SegmentedButton<MediaFilter>(
              key: const ValueKey('cards-filter'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: MediaFilter.all,
                  label: Text(
                    'All ${cards.length}',
                    key: const ValueKey('cards-filter-all'),
                    semanticsLabel: 'All, ${ideaCount(cards.length)}',
                  ),
                ),
                if (videos > 0)
                  ButtonSegment(
                    value: MediaFilter.videos,
                    icon: const Icon(Icons.smart_display_outlined, size: 18),
                    label: Text(
                      'Videos $videos',
                      key: const ValueKey('cards-filter-videos'),
                      semanticsLabel: 'Videos, ${videoCount(videos)}',
                    ),
                  ),
                if (images > 0)
                  ButtonSegment(
                    value: MediaFilter.images,
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: Text(
                      'Images $images',
                      key: const ValueKey('cards-filter-images'),
                      semanticsLabel: 'Images, ${imageCount(images)}',
                    ),
                  ),
              ],
              selected: {filter},
              onSelectionChanged: (s) =>
                  ref.read(cardsFilterProvider(page).notifier).set(s.first),
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
