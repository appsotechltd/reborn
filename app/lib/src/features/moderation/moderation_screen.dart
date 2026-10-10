import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../contribute/contribution_tile.dart';

class ModerationScreen extends ConsumerWidget {
  const ModerationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (!session.isModerator) {
      return Scaffold(
        appBar: AppBar(title: const Text('Moderation')),
        body: const Center(child: Text('Moderation is for moderators only.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Moderation queue')),
      body: ref
          .watch(moderationQueueProvider)
          .when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(
              error: e,
              onRetry: () => ref.invalidate(moderationQueueProvider),
            ),
            data: (list) => list.isEmpty
                ? const Center(child: Text('The queue is empty.'))
                : RefreshIndicator(
                    onRefresh: () =>
                        ref.refresh(moderationQueueProvider.future),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: [
                        for (final c in list)
                          ReadingWidth(child: _QueueItem(c: c)),
                      ],
                    ),
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
