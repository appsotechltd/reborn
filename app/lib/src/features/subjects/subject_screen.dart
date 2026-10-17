import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../post/share.dart';
import '../summary/summary_controller.dart';
import '../summary/summary_widgets.dart';
import 'subject_controller.dart';
import 'subject_widgets.dart';

/// A subject: a short course of guides followed one after the other. Shows
/// what it covers, how far the reader is, each guide in order (done, in
/// progress or not started) and one button to start, continue with the
/// next guide, or read it again once every guide is done.
class SubjectScreen extends ConsumerWidget {
  const SubjectScreen({super.key, required this.subjectId});
  final String subjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(subjectProvider(subjectId));
    final d = async.value?.value;
    return Scaffold(
      appBar: AppBar(
        leading: exitLeading(context),
        title: Text(
          d?.subject.title ?? 'Subject',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (d != null)
            ShareLinkButton(
              key: const ValueKey('subject-share'),
              title: d.subject.title,
              path: subjectPath(subjectId),
            ),
        ],
      ),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(subjectProvider(subjectId)),
        ),
        data: (f) => RefreshIndicator(
          onRefresh: () => ref.refresh(subjectProvider(subjectId).future),
          child: _body(context, ref, f.value),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, SubjectDetail d) {
    final theme = Theme.of(context);
    final c = Candlelight.of(context);
    final s = d.subject;
    final guides = d.guides;
    final local = ref.watch(summaryPlacesProvider);
    final progress = guideProgress(guides, local);
    final finished = progress.where((p) => p?.finished ?? false).length;
    final started = progress.any((p) => p?.started ?? false);
    final next = nextGuide(progress);

    final String label;
    final String? open;
    if (guides.isEmpty) {
      label = 'Start';
      open = null;
    } else if (next == null) {
      label = 'Read again';
      open = guides.first.id;
    } else if (!started) {
      label = 'Start';
      open = guides.first.id;
    } else {
      label = 'Continue: ${guides[next].title}';
      open = guides[next].id;
    }

    return ListView(
      key: const ValueKey('subject-list'),
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        ReadingWidth(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SubjectCoverBox(
                  subject: s,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (s.cover != null) const SizedBox(height: 96),
                      Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Icon(
                            Icons.auto_stories_outlined,
                            size: 16,
                            color: CandlelightTokens.amber,
                          ),
                          Text(
                            'SUBJECT  ·  ${s.meta.toUpperCase()}',
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
                        s.title,
                        style: const TextStyle(
                          fontFamily: kDisplayFont,
                          fontSize: 30,
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                          color: SubjectCoverBox.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                if (s.description.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(s.description, style: theme.textTheme.bodyLarge),
                ],
                if (started && guides.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  SubjectProgressLine(
                    key: const ValueKey('subject-progress'),
                    finished: finished,
                    count: guides.length,
                  ),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    key: const ValueKey('subject-start'),
                    onPressed: open == null
                        ? null
                        : () => context.push(summaryPath(open!)),
                    icon: Icon(
                      next == null && guides.isNotEmpty
                          ? Icons.replay
                          : Icons.arrow_forward,
                      size: 18,
                    ),
                    label: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 24, 4, 4),
                  child: Text('Guides', style: theme.textTheme.titleLarge),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    'Read them in order; each one builds on the last.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
                  ),
                ),
              ],
            ),
          ),
        ),
        for (var i = 0; i < guides.length; i++)
          ReadingWidth(
            child: _GuideTile(
              number: i + 1,
              guide: guides[i],
              progress: progress[i],
              isNext: i == next && started,
            ),
          ),
      ],
    );
  }
}

/// One guide in the subject's list: its number (a tick once done), title,
/// length and the reader's place. Opens the reader where they stopped.
class _GuideTile extends StatelessWidget {
  const _GuideTile({
    required this.number,
    required this.guide,
    required this.progress,
    required this.isNext,
  });
  final int number;
  final Summary guide;
  final SummaryProgress? progress;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = Candlelight.of(context);
    final done = progress?.finished ?? false;
    final reading = !done && (progress?.started ?? false);
    final state = done
        ? 'Done'
        : reading
        ? 'In progress · part ${progress!.position + 1} of ${guide.partCount}'
        : 'Not started';
    final Widget badge = done
        ? const Icon(
            Icons.check_circle,
            key: ValueKey('guide-done'),
            color: CandlelightTokens.amber,
            size: 30,
          )
        : Container(
            key: ValueKey(reading ? 'guide-reading' : 'guide-not-started'),
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: reading ? c.inset : null,
              border: Border.all(
                color: reading ? CandlelightTokens.amber : c.line,
                width: reading ? 2 : 1,
              ),
            ),
            child: Text(
              '$number',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: reading ? c.amberText : c.muted,
              ),
            ),
          );
    return Semantics(
      label: 'Guide $number: ${guide.title}, ${state.toLowerCase()}',
      excludeSemantics: true,
      button: true,
      child: InkWell(
        key: ValueKey('subject-guide-${guide.id}'),
        onTap: () => context.push(summaryPath(guide.id)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
          child: Row(
            children: [
              badge,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$number. ${guide.title}',
                      style: TextStyle(
                        fontFamily: kDisplayFont,
                        fontSize: 17,
                        height: 1.25,
                        fontWeight: isNext ? FontWeight.w700 : FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${guide.meta}  ·  $state',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: done || reading ? c.amberText : c.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}
