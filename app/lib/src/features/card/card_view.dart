import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../data/speaker.dart';
import '../stashes/stash_picker.dart';
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
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 24),
  });

  final IdeaCard card;

  /// Optional badge above the title, e.g. "Today's idea".
  final String? label;
  final bool showActions;
  final EdgeInsets padding;

  String? get _disclaimer =>
      card.disclaimer ?? (card.health ? kHealthDisclaimerFallback : null);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (label != null)
                _Pill(
                  text: label!,
                  color: scheme.primary,
                  onColor: scheme.onPrimary,
                ),
              _Pill(
                text: topicName,
                color: scheme.secondaryContainer,
                onColor: scheme.onSecondaryContainer,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(card.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 14),
          if (card.explainer != null) ...[
            ExplainerPlayer(explainer: card.explainer!, title: card.title),
            const SizedBox(height: 16),
          ],
          for (final p in paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(p, style: theme.textTheme.bodyLarge),
            ),
          if (card.quote != null && card.quote!.trim().isNotEmpty)
            _QuoteBlock(quote: card.quote!, locator: card.locator),
          const SizedBox(height: 8),
          _ApplyIt(text: card.applyIt),
          if (_disclaimer != null) ...[
            const SizedBox(height: 12),
            _Disclaimer(text: _disclaimer!),
          ],
          const SizedBox(height: 16),
          _Credit(card: card),
          if (showActions) ...[
            const SizedBox(height: 12),
            _CardActions(card: card),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color, required this.onColor});
  final String text;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: onColor, fontWeight: FontWeight.w600),
    ),
  );
}

class _QuoteBlock extends StatelessWidget {
  const _QuoteBlock({required this.quote, this.locator});
  final String quote;
  final String? locator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '“${quote.trim()}”',
            style: theme.textTheme.titleMedium?.copyWith(
              fontStyle: FontStyle.italic,
              fontFamily: 'serif',
              fontFamilyFallback: const ['Georgia', 'Times New Roman'],
              height: 1.5,
              color: scheme.onSurfaceVariant,
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
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt, size: 20, color: scheme.onPrimaryContainer),
              const SizedBox(width: 6),
              Text(
                'Apply it',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onPrimaryContainer,
              fontSize: 17,
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
    return Container(
      key: const ValueKey('card-disclaimer'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.health_and_safety_outlined,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _Credit extends StatelessWidget {
  const _Credit({required this.card});
  final IdeaCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      key: const ValueKey('card-credit'),
      borderRadius: BorderRadius.circular(8),
      onTap: card.source.id.isEmpty
          ? null
          : () =>
                context.push('/sources/${Uri.encodeComponent(card.source.id)}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                card.credit,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  decoration: TextDecoration.underline,
                  decorationColor: scheme.outline,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _CardActions extends ConsumerWidget {
  const _CardActions({required this.card});
  final IdeaCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speaker = ref.watch(speakerProvider);
    return ListenableBuilder(
      listenable: speaker,
      builder: (context, _) {
        final speaking = speaker.speakingId == card.id;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            speaking
                ? FilledButton.tonalIcon(
                    onPressed: speaker.stop,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  )
                : OutlinedButton.icon(
                    onPressed: () => speaker.speak(card.id, card.spokenText),
                    icon: const Icon(Icons.headphones_outlined),
                    label: const Text('Listen'),
                  ),
            OutlinedButton.icon(
              onPressed: () => showStashPicker(context, ref, card),
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('Stash'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: shareText(card)));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Idea copied — paste it anywhere'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.ios_share),
              label: const Text('Share'),
            ),
          ],
        );
      },
    );
  }
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
      ..writeln('“${card.quote!.trim()}”');
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
