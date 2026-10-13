import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../listen/listen_controller.dart';
import '../../layout/adaptive.dart';
import '../post/share.dart';
import '../stashes/stash_picker.dart';
import '../../theme.dart';
import 'explainer_player.dart';

const kHealthDisclaimerFallback =
    'This is general information, not medical advice.';

/// The full reading view of an idea card. Credit is always shown, and the
/// health disclaimer whenever the card has one.
class IdeaCardView extends ConsumerWidget {
  const IdeaCardView({
    super.key,
    required this.card,
    this.label,
    this.showActions = true,
    this.showShare = true,
    this.showVideo = true,
    this.showTopic = true,
    this.byline,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 24),
  });

  final IdeaCard card;

  /// Optional badge above the title, e.g. "Today's idea".
  final String? label;
  final bool showActions;

  /// False when the surrounding post view has its own Share button.
  final bool showShare;

  /// False on the TV idea page, which shows the title beside the card and
  /// plays the video full screen from its own button: neither video nor
  /// title is repeated here.
  final bool showVideo;

  /// False on the TV idea page, whose left column already shows the topic.
  final bool showTopic;

  /// The source line ("Meditations · Marcus Aurelius"), shown under the
  /// title, as on the feed card: topic, title, then source.
  final Widget? byline;
  final EdgeInsets padding;

  String? get _disclaimer =>
      card.disclaimer ?? (card.health ? kHealthDisclaimerFallback : null);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final topicName = ref.watch(topicNamesProvider)[card.topic] ?? card.topic;
    final paragraphs = card.body
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label != null || showTopic) ...[
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (label != null) _Pill(text: label!),
                if (showTopic) CategoryTag(topicName),
              ],
            ),
            const SizedBox(height: 10),
          ],
          // The title is always written out, video or not: the poster's own
          // printed title is art (and gone when the video fails to load).
          if (showVideo) ...[
            Text(
              card.title,
              key: const ValueKey('card-title'),
              style: cardPageTitleStyle(context),
            ),
            const SizedBox(height: 6),
          ],
          if (card.explainer != null && showVideo) ...[
            const SizedBox(height: 4),
            ExplainerPlayer(
              explainer: card.explainer!,
              title: card.title,
              autoplayId: card.id,
            ),
            const SizedBox(height: 10),
          ],
          ?byline,
          // The health or support note comes before the reading, so it's
          // seen first.
          if (_disclaimer != null) ...[
            const SizedBox(height: 14),
            _Disclaimer(text: _disclaimer!),
          ],
          const SizedBox(height: 16),
          for (final p in paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(p, style: theme.textTheme.bodyLarge),
            ),
          if (card.quote != null && card.quote!.trim().isNotEmpty)
            _QuoteBlock(quote: card.quote!, locator: card.locator),
          const SizedBox(height: 8),
          _ApplyIt(text: card.applyIt),
          if (showActions) ...[
            const SizedBox(height: 16),
            _CardActions(card: card, showShare: showShare),
          ],
        ],
      ),
    );
  }
}

/// The article-style title of the card page: 30px on phones, 36px from
/// tablet width up (web: text-3xl / sm:text-4xl Fraunces).
TextStyle? cardPageTitleStyle(BuildContext context) {
  final wide = MediaQuery.sizeOf(context).width >= WindowSize.mediumMin;
  final size = wide ? 36.0 : 30.0;
  return Theme.of(context).textTheme.headlineSmall
      ?.copyWith(fontSize: size, height: 1.2, letterSpacing: -0.015 * size);
}

/// Amber pill for a badge such as "Today's idea".
class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Candlelight.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: ShapeDecoration(color: c.amber, shape: const StadiumBorder()),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: c.onAmber, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _QuoteBlock extends StatelessWidget {
  const _QuoteBlock({required this.quote, this.locator});
  final String quote;
  final String? locator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = Candlelight.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: c.oxblood, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayQuote(quote),
            style: TextStyle(
              fontFamily: kDisplayFont,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.italic,
              fontSize: 18,
              height: 1.45,
              color: c.ink2,
            ),
          ),
          if (locator != null) ...[
            const SizedBox(height: 6),
            Text('— $locator', style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _ApplyIt extends StatelessWidget {
  const _ApplyIt({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = Candlelight.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: c.inset,
        borderRadius: BorderRadius.circular(CandlelightTokens.radiusInset),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CategoryTag('Apply it'),
          const SizedBox(height: 4),
          Text(
            text,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 16,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = Candlelight.of(context);
    // Health/support note: ink-on-inset with a hairline, readable in both modes.
    return Container(
      key: const ValueKey('card-disclaimer'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.inset,
        borderRadius: BorderRadius.circular(CandlelightTokens.radiusInset),
        border: Border.all(color: c.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.health_and_safety_outlined, size: 18, color: c.amberText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurface, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardActions extends ConsumerWidget {
  const _CardActions({required this.card, required this.showShare});
  final IdeaCard card;
  final bool showShare;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Listen plays this card's recording, or reads it with the device
    // voice when it has none (see ListenController.playCard).
    final playing = ref.watch(
      listenProvider.select(
        (s) => s.active && s.playing && s.current?.card.id == card.id,
      ),
    );
    final listen = ref.read(listenProvider.notifier);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        playing
            ? FilledButton.tonalIcon(
                onPressed: listen.stop,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              )
            : OutlinedButton.icon(
                onPressed: () => listen.playCard(card),
                icon: const Icon(Icons.headphones_outlined),
                label: const Text('Listen'),
              ),
        OutlinedButton.icon(
          onPressed: () => showStashPicker(context, ref, card),
          icon: const Icon(Icons.bookmark_add_outlined),
          label: const Text('Stash'),
        ),
        if (showShare)
          Builder(
            builder: (context) => OutlinedButton.icon(
              onPressed: () => sharePost(
                context,
                ref,
                Post.fromCard(card),
                countLocally: false,
              ),
              icon: const Icon(Icons.ios_share),
              label: const Text('Share'),
            ),
          ),
      ],
    );
  }
}

/// A card's quote as shown: wrapped in curly double quotes, unless the
/// text already carries its own double quote marks (speech inside the
/// quote, or a quote stored with its outer pair), which would otherwise
/// show doubled ("“"Begin, friend," ..."”").
String displayQuote(String quote) {
  final q = quote.trim();
  if (RegExp('["“”]').hasMatch(q)) return q;
  return '“$q”';
}

/// Plain-text version of a card for sharing, always with its credit.
String shareText(IdeaCard card) {
  final b = StringBuffer()
    ..writeln(card.title)
    ..writeln()
    ..writeln(card.body.trim());
  if (card.quote != null) {
    b
      ..writeln()
      ..writeln(displayQuote(card.quote!));
  }
  b
    ..writeln()
    ..writeln('Apply it: ${card.applyIt}');
  if (card.disclaimer != null) {
    b
      ..writeln()
      ..writeln(card.disclaimer);
  }
  b
    ..writeln()
    ..writeln(card.credit)
    ..write('— via Reborn');
  return b.toString();
}
