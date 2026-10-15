import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../data/providers.dart';
import '../features/daily/daily_screen.dart';
import '../features/streak/streak_card.dart';
import '../theme.dart';

/// Spine colours for generated book covers: deep, warm and distinct from
/// each other in both modes (light text sits on all of them).
const _coverColors = [
  (Color(0xFF6B2A22), Color(0xFF2E1210)),
  (Color(0xFF3E4A5A), Color(0xFF1D242E)),
  (Color(0xFF4E5B3A), Color(0xFF222A18)),
  (Color(0xFF6F4E7A), Color(0xFF2E1F36)),
  (Color(0xFF8A5A1E), Color(0xFF3A240A)),
  (Color(0xFF2F5A58), Color(0xFF122826)),
  (Color(0xFF7A3B4E), Color(0xFF331520)),
  (Color(0xFF4A4038), Color(0xFF1F1A15)),
];

/// The same colour pair for the same book every time.
(Color, Color) coverColorsFor(String id) {
  var h = 0;
  for (final c in id.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return _coverColors[h % _coverColors.length];
}

/// A small typeset book cover for books with no artwork: a warm spine
/// colour picked from the book id, with the title's initial in Fraunces.
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.id,
    required this.title,
    this.width = 40,
    this.height = 56,
  });

  final String id;
  final String title;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final (top, bottom) = coverColorsFor(id);
    return ExcludeSemantics(
      child: Container(
        width: width,
        height: height,
        padding: EdgeInsets.all(width * 0.12),
        alignment: Alignment.bottomLeft,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [top, bottom],
          ),
          border: const Border(
            left: BorderSide(color: Color(0x1FFFFFFF), width: 3),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              offset: Offset(0, 6),
              blurRadius: 12,
              spreadRadius: -6,
            ),
          ],
        ),
        child: Text(
          _initial(title),
          style: TextStyle(
            fontFamily: kDisplayFont,
            fontWeight: FontWeight.w600,
            fontSize: width * 0.42,
            height: 1,
            color: const Color(0xFFF3E4CA),
          ),
        ),
      ),
    );
  }

  /// The first letter of the title, skipping "The" and "A".
  static String _initial(String title) {
    final words = title.trim().split(RegExp(r'\s+'));
    final skip = {'the', 'a', 'an'};
    final w = words.length > 1 && skip.contains(words.first.toLowerCase())
        ? words[1]
        : words.first;
    return w.isEmpty ? '' : w.characters.first.toUpperCase();
  }
}

/// The top of a feed post: the card's picture, or for a card without one a
/// warm panel carrying its quote (or its title's first words), so every
/// post opens with something to look at. The topic sits on top.
class PostCover extends StatelessWidget {
  const PostCover({super.key, required this.card, required this.topic});
  final IdeaCard card;
  final String topic;

  static const _onDark = Color(0xFFF3B65A);
  static const _chipFill = Color(0x9E14110E);

  @override
  Widget build(BuildContext context) {
    final image = card.image;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final c = Candlelight.of(context);
    Widget art;
    if (image != null) {
      art = Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: CandlelightTokens.videoBase),
          Semantics(
            image: true,
            label: image.caption,
            child: Image.network(
              resolveMediaUrl(image.url),
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.55, 1],
                colors: [
                  Theme.of(context).cardColor.withValues(alpha: 0),
                  Theme.of(context).cardColor,
                ],
              ),
            ),
          ),
        ],
      );
    } else {
      final quote = card.quote?.trim() ?? '';
      final line = quote.isNotEmpty ? _firstSentence(quote) : null;
      art = DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? const [Color(0xFF3A2B17), Color(0xFF221A12)]
                : const [Color(0xFFFBEBD0), Color(0xFFF3D7A6)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: 14,
              bottom: -70,
              child: ExcludeSemantics(
                child: Text(
                  '“',
                  style: TextStyle(
                    fontFamily: kDisplayFont,
                    fontSize: 200,
                    height: 1,
                    color: c.amberText.withValues(alpha: dark ? 0.18 : 0.13),
                  ),
                ),
              ),
            ),
            if (line != null)
              Positioned(
                left: 20,
                right: 20,
                bottom: 18,
                child: Text(
                  line,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: kDisplayFont,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                    height: 1.32,
                    color: dark
                        ? CandlelightTokens.dark.onAmberContainer
                        : CandlelightTokens.light.onAmberContainer,
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        art,
        if (topic.isNotEmpty)
          Positioned(
            left: 14,
            top: 14,
            child: ExcludeSemantics(
              child: _CoverChip(
                text: topic.toUpperCase(),
                fill: image != null || dark
                    ? _chipFill
                    : const Color(0xB3FFFFFF),
                color: image != null || dark ? _onDark : c.amberText,
              ),
            ),
          ),
      ],
    );
  }

  /// The quote's opening sentence, short enough for the cover.
  static String _firstSentence(String quote) {
    final q = quote.replaceAll(RegExp(r'["“”]'), '').trim();
    final m = RegExp(r'^.{20,}?[.;!?](\s|$)').firstMatch(q);
    final s = (m?.group(0) ?? q).trim();
    return s.length > 140 ? '${s.substring(0, 137).trimRight()}…' : s;
  }
}

class _CoverChip extends StatelessWidget {
  const _CoverChip({
    required this.text,
    required this.fill,
    required this.color,
  });
  final String text;
  final Color fill;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
    decoration: ShapeDecoration(color: fill, shape: const StadiumBorder()),
    child: Text(
      text,
      style: TextStyle(
        fontFamily: kBodyFont,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: color,
      ),
    ),
  );
}

/// The streak as a small flame chip in the top bar. Tapping it opens
/// today's idea and the full streak (goal, the last seven days).
class StreakChip extends ConsumerWidget {
  const StreakChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(sessionProvider.select((s) => s.signedIn));
    if (!signedIn) return const SizedBox.shrink();
    final streak = ref.watch(streakProvider).value;
    final days = streak?.current ?? 0;
    final c = Candlelight.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: '$days day streak. Open today\'s idea and your streak',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          key: const ValueKey('streak-chip'),
          color: dark
              ? const Color(0x1AE9A23B)
              : CandlelightTokens.light.amberContainer,
          shape: StadiumBorder(
            side: BorderSide(
              color: dark ? const Color(0x47E9A23B) : const Color(0xFFF0D9B0),
            ),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => showTodaySheet(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(9, 7, 12, 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_fire_department_rounded,
                    size: 18,
                    color: days > 0 ? CandlelightTokens.amber : c.muted,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '$days',
                    style: TextStyle(
                      fontFamily: kBodyFont,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: dark ? const Color(0xFFF3B65A) : c.amberText,
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

/// Today's idea and the streak in a sheet, off the feed so every swipe
/// page is just the post.
Future<void> showTodaySheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.only(bottom: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [DailyBanner(), StreakCard()],
      ),
    ),
  ),
);
