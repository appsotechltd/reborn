import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../theme.dart';
import 'subject_controller.dart';

/// The subject's page.
String subjectPath(String id) => '/subjects/${Uri.encodeComponent(id)}';

/// A subject's cover: its first guide's picture on the dark Candlelight
/// ground (like a summary's cover), or the flame's glow when it has none.
class SubjectCoverBox extends StatelessWidget {
  const SubjectCoverBox({
    super.key,
    required this.subject,
    this.size,
    this.child,
    this.padding = EdgeInsets.zero,
  });
  final Subject subject;

  /// Square side for a thumbnail; null fills the width.
  final double? size;
  final Widget? child;
  final EdgeInsetsGeometry padding;

  static const bg = Color(0xFF1F1710);
  static const ink = Color(0xFFF2E8D8);
  static const ink2 = Color(0xFFD9CDBA);

  @override
  Widget build(BuildContext context) {
    final cover = subject.cover;
    return Container(
      width: size,
      height: size,
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(CandlelightTokens.radiusInset),
        image: cover == null
            ? null
            : DecorationImage(
                image: NetworkImage(resolveMediaUrl(cover.url)),
                fit: BoxFit.cover,
                colorFilter: ColorFilter.mode(
                  child == null
                      ? const Color(0x331F1710)
                      : const Color(0xA61F1710),
                  BlendMode.srcOver,
                ),
                onError: (_, _) {},
              ),
        gradient: cover != null
            ? null
            : const RadialGradient(
                center: Alignment(0.8, -1.1),
                radius: 1.3,
                colors: [Color(0x47E9A23B), bg],
                stops: [0, 0.6],
              ),
      ),
      child:
          child ??
          (cover == null
              ? const Center(
                  child: Icon(
                    Icons.auto_stories_outlined,
                    color: CandlelightTokens.amber,
                  ),
                )
              : Semantics(label: cover.caption, image: true)),
    );
  }
}

/// "3 of 7 done" with a bar, from the guides finished.
class SubjectProgressLine extends StatelessWidget {
  const SubjectProgressLine({
    super.key,
    required this.finished,
    required this.count,
    this.compact = false,
  });
  final int finished;
  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = Candlelight.of(context);
    final done = finished.clamp(0, count);
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: count == 0 ? 0 : done / count,
              minHeight: compact ? 4 : 6,
              color: CandlelightTokens.amber,
              backgroundColor: c.inset,
              semanticsLabel: 'Guides done',
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '$done of $count done',
          style: theme.textTheme.bodySmall?.copyWith(color: c.muted),
        ),
      ],
    );
  }
}

/// A subject in a row or list: cover, title, "7 guides · 60 min" and, when
/// signed in and started, how many guides are done. Opens the subject.
class SubjectCard extends StatelessWidget {
  const SubjectCard({super.key, required this.subject});
  final Subject subject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = Candlelight.of(context);
    final v = subject.viewer;
    return Card(
      key: ValueKey('subject-card-${subject.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(subjectPath(subject.id)),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              SubjectCoverBox(subject: subject, size: 64),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      subject.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: kDisplayFont,
                        fontSize: 18,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subject.meta,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: c.muted,
                      ),
                    ),
                    if (v != null && (v.started || v.finished > 0)) ...[
                      const SizedBox(height: 6),
                      SubjectProgressLine(
                        key: ValueKey('subject-progress-${subject.id}'),
                        finished: v.finished,
                        count: subject.guideCount,
                        compact: true,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Above a topic's posts: its subjects, courses of guides to follow in
/// order. Nothing at all when the topic has none (or they can't load).
class SubjectsRow extends ConsumerWidget {
  const SubjectsRow({super.key, required this.topic});
  final String topic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjects =
        ref.watch(subjectsProvider(topic)).value?.value ?? const <Subject>[];
    if (subjects.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      key: ValueKey('subjects-row-$topic'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Subjects',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: '  ·  guides to follow in order',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Candlelight.of(context).muted,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          height: 92,
          child: LayoutBuilder(
            builder: (context, box) {
              // One subject takes the row; more scroll sideways.
              final width = subjects.length == 1
                  ? (box.maxWidth - 32).clamp(0.0, 480.0)
                  : 300.0;
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: subjects.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) => SizedBox(
                  width: width,
                  child: SubjectCard(subject: subjects[i]),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}
