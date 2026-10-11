import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../contribute/contribution_tile.dart';

/// Moderators' queue: contributions waiting for a decision, then comments
/// people have reported (three reports hide one until a moderator hides or
/// restores it), as on the web's moderation page.
class ModerationScreen extends ConsumerWidget {
  const ModerationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (!session.isModerator) {
      return Scaffold(
        appBar: AppBar(
          leading: exitLeading(context),
          title: const Text('Moderation'),
        ),
        body: const Center(child: Text('Moderation is for moderators only.')),
      );
    }
    final theme = Theme.of(context);
    final queue = ref.watch(moderationQueueProvider);
    final reported = ref.watch(reportedCommentsProvider);

    Widget heading(String text, {Key? key}) => ReadingWidth(
      child: Padding(
        key: key,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
        child: SizedBox(
          width: double.infinity,
          child: Text(text, style: theme.textTheme.titleMedium),
        ),
      ),
    );
    Widget note(String text) => ReadingWidth(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: SizedBox(
          width: double.infinity,
          child: Text(text, style: theme.textTheme.bodyMedium),
        ),
      ),
    );
    List<Widget> section<T>(
      AsyncValue<List<T>> value,
      VoidCallback retry,
      String empty,
      Widget Function(T) item,
    ) => value.when(
      loading: () => const [
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
      error: (e, _) => [
        ReadingWidth(
          child: ErrorView(error: e, onRetry: retry),
        ),
      ],
      data: (list) => list.isEmpty
          ? [note(empty)]
          : [for (final x in list) ReadingWidth(child: item(x))],
    );

    return Scaffold(
      appBar: AppBar(
        leading: exitLeading(context),
        title: const Text('Moderation queue'),
      ),
      body: RefreshIndicator(
        onRefresh: () => Future.wait([
          ref.refresh(moderationQueueProvider.future),
          ref.refresh(reportedCommentsProvider.future),
        ]),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            heading('Contributions'),
            ...section(
              queue,
              () => ref.invalidate(moderationQueueProvider),
              'No contributions are waiting.',
              (c) => _QueueItem(c: c),
            ),
            heading(
              'Reported comments',
              key: const ValueKey('reported-comments'),
            ),
            ReadingWidth(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: SizedBox(
                  width: double.infinity,
                  child: Text(
                    'Three reports hide a comment until you decide. Hiding or '
                    'restoring clears its reports.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
            ),
            ...section(
              reported,
              () => ref.invalidate(reportedCommentsProvider),
              'No reported comments.',
              (c) => _ReportedItem(c: c),
            ),
          ],
        ),
      ),
    );
  }
}

/// A reported comment with Hide and Restore.
class _ReportedItem extends ConsumerStatefulWidget {
  const _ReportedItem({required this.c});
  final ReportedComment c;

  @override
  ConsumerState<_ReportedItem> createState() => _ReportedItemState();
}

class _ReportedItemState extends ConsumerState<_ReportedItem> {
  bool _busy = false;

  /// 'Hidden' or 'Restored' once decided here.
  String? _decided;

  Future<void> _decide(bool hide) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .moderateComment(widget.c.id, hide: hide);
      if (mounted) {
        setState(() {
          _busy = false;
          _decided = hide ? 'Hidden' : 'Restored';
        });
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.c;
    final c = r.comment;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hidden = _decided == null ? r.hidden : _decided == 'Hidden';
    return Card(
      key: ValueKey('reported-${r.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${c.author.displayName} · @${c.author.handle} · '
              '${timeAgo(c.createdAt)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text(c.body, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  decoration: ShapeDecoration(
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: hidden ? scheme.error : scheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: Text(
                    hidden ? 'Hidden' : 'Visible',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: hidden ? scheme.error : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  '${r.reports} ${r.reports == 1 ? 'report' : 'reports'}'
                  '${r.reasons.isEmpty ? '' : ': ${r.reasons.toSet().join(', ')}'}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_decided != null)
              Text('$_decided ✓', style: theme.textTheme.labelLarge)
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : () => _decide(false),
                    child: const Text('Restore'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : () => _decide(true),
                    child: const Text('Hide'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _QueueItem extends ConsumerStatefulWidget {
  const _QueueItem({required this.c});
  final Contribution c;

  @override
  ConsumerState<_QueueItem> createState() => _QueueItemState();
}

class _QueueItemState extends ConsumerState<_QueueItem> {
  bool _busy = false;

  Future<String?> _askNote({required bool required}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(required ? 'Reject — reason' : 'Approve'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          decoration: InputDecoration(
            labelText: required
                ? 'Note for the contributor'
                : 'Note (optional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final t = controller.text.trim();
              if (required && t.isEmpty) return;
              Navigator.pop(ctx, t);
            },
            child: Text(required ? 'Reject' : 'Approve'),
          ),
        ],
      ),
    );
  }

  Future<void> _act(bool approve) async {
    final note = await _askNote(required: !approve);
    if (note == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final repo = ref.read(repositoryProvider);
      if (approve) {
        await repo.approve(widget.c.id, note: note);
      } else {
        await repo.reject(widget.c.id, note);
      }
      messenger.showSnackBar(
        SnackBar(content: Text(approve ? 'Approved' : 'Rejected')),
      );
      ref.invalidate(moderationQueueProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final names = ref.watch(topicNamesProvider);
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(names[c.topic] ?? c.topic, style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(c.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ContributionDetails(c: c),
            const SizedBox(height: 4),
            Text(
              '${wordCount(c.body)} words',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : () => _act(false),
                  child: const Text('Reject'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : () => _act(true),
                  child: const Text('Approve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
