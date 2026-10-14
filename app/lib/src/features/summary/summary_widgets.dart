import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../theme.dart';
import '../listen/listen_controller.dart';
import 'summary_controller.dart';

/// The reader's page; [part] is one-based, [all] the one long page.
String summaryPath(String id, {int? part, bool all = false}) {
  final q = <String, String>{
    if (all) 'view': 'all',
    if (part != null && part > 1) 'part': '$part',
  };
  return Uri(
    path: '/summaries/${Uri.encodeComponent(id)}',
    queryParameters: q.isEmpty ? null : q,
  ).toString();
}

/// Names a summary's parts for Listen mode (see ListenState.queueKey).
String summaryListenKey(String id) => 'summary:$id';

/// Plays a summary start to finish in Listen mode from part [from], loading
/// its parts when they aren't given, and opens the player.
Future<void> listenToSummary(
  BuildContext context,
  WidgetRef ref,
  String id, {
  List<IdeaCard>? parts,
  int from = 0,
}) async {
  var cards = parts;
  if (cards == null) {
    try {
      cards = (await ref.read(repositoryProvider).summary(id)).value.parts;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't load this summary.")),
        );
      }
      return;
    }
  }
  if (cards.isEmpty) return;
  await ref
      .read(listenProvider.notifier)
      .startCards(
        cards,
        index: from.clamp(0, cards.length - 1),
        key: summaryListenKey(id),
      );
  if (context.mounted) context.push('/listen');
}

/// The summary's cover: always the dark Candlelight look (like videos), so it
/// stands out in the feed as something bigger than one card.
class SummaryCover extends StatelessWidget {
  const SummaryCover({super.key, required this.summary, this.large = false});
  final Summary summary;
  final bool large;

  static const _bg = Color(0xFF1F1710);
  static const _ink = Color(0xFFF2E8D8);
  static const _ink2 = Color(0xFFD9CDBA);
  static const _line = Color(0xFF4A3E32);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: ValueKey('summary-cover-${summary.id}'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(9),
        gradient: const RadialGradient(
          center: Alignment(0.8, -1.1),
          radius: 1.3,
          colors: [Color(0x47E9A23B), _bg],
          stops: [0, 0.6],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Icon(
                Icons.library_books_outlined,
                size: 16,
                color: CandlelightTokens.amber,
              ),
              Text(
                '${summary.coverageLabel.toUpperCase()}'
                '${summary.topicName.isEmpty ? '' : '  ·  ${summary.topicName.toUpperCase()}'}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: CandlelightTokens.amber,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            summary.title,
            style: TextStyle(
              fontFamily: kDisplayFont,
              fontSize: large ? 30 : 24,
              height: 1.15,
              fontWeight: FontWeight.w600,
              color: _ink,
            ),
          ),
          if (summary.byline.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              summary.byline,
              style: theme.textTheme.bodySmall?.copyWith(color: _ink2),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: _line),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              summary.meta,
              style: theme.textTheme.labelSmall?.copyWith(
                color: _ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Part 4 of 30" with a bar, or "Finished".
class SummaryProgressLine extends StatelessWidget {
  const SummaryProgressLine({
    super.key,
    required this.progress,
    required this.parts,
  });
  final SummaryProgress progress;
  final int parts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = Candlelight.of(context);
    final done = progress.finished
        ? parts
        : (progress.position + 1).clamp(0, parts);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: parts == 0 ? 0 : done / parts,
              minHeight: 6,
              color: CandlelightTokens.amber,
              backgroundColor: c.inset,
              semanticsLabel: 'Reading progress',
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          progress.finished ? 'Finished' : 'Part $done of $parts',
          style: theme.textTheme.bodySmall?.copyWith(color: c.muted),
        ),
      ],
    );
  }
}

/// A summary post in the timeline or a list: its cover, what it is, where
/// the reader got to, and Start reading / Continue (one part per screen),
/// Read it all (one long page) and Listen.
class SummaryPostCard extends ConsumerWidget {
  const SummaryPostCard({super.key, required this.summary, this.large = false});
  final Summary summary;
  final bool large;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final local = ref.watch(summaryPlacesProvider.select((m) => m[summary.id]));
    final progress = bestProgress(summary.viewer, local);
    final from = progress?.resumeIndex(summary.partCount) ?? 0;
    final continuing = (progress?.started ?? false) && from > 0;
    final finished = progress?.finished ?? false;
    return Card(
      key: ValueKey('summary-post-${summary.id}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () =>
                  context.push(summaryPath(summary.id, part: from + 1)),
              child: SummaryCover(summary: summary, large: large),
            ),
            if (summary.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                summary.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (progress != null && progress.started) ...[
              const SizedBox(height: 12),
              SummaryProgressLine(progress: progress, parts: summary.partCount),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('summary-start'),
                  onPressed: () =>
                      context.push(summaryPath(summary.id, part: from + 1)),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: Text(
                    continuing
                        ? 'Continue'
                        : (finished ? 'Read again' : 'Start reading'),
                  ),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('summary-read-all'),
                  onPressed: () =>
                      context.push(summaryPath(summary.id, all: true)),
                  icon: const Icon(Icons.notes, size: 18),
                  label: const Text('Read it all'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('summary-listen'),
                  onPressed: () =>
                      listenToSummary(context, ref, summary.id, from: from),
                  icon: const Icon(Icons.headphones_outlined, size: 18),
                  label: const Text('Listen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A summary post as one page of the phone swipe feed.
class SwipeSummaryPage extends StatelessWidget {
  const SwipeSummaryPage({
    super.key,
    required this.summary,
    this.header = const [],
    this.footer,
  });
  final Summary summary;
  final List<Widget> header;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...header,
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: c.maxHeight),
                      child: Center(
                        child: SummaryPostCard(summary: summary, large: true),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ?footer,
    ],
  );
}
