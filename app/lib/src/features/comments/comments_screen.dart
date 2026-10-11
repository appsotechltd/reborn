import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../blocks/block_actions.dart';
import '../post/post_store.dart';
import 'comments_controller.dart';

/// Comments on a post, with one level of replies under each comment.
class CommentsScreen extends ConsumerStatefulWidget {
  const CommentsScreen({super.key, required this.postId, this.post});
  final String postId;

  /// The post, when opened from one (keeps its comment count in sync).
  final Post? post;

  @override
  ConsumerState<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends ConsumerState<CommentsScreen> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  Comment? _replyTo;
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  CommentsController get _controller =>
      ref.read(commentsProvider(widget.postId).notifier);

  void _snack(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    if (!ensureSignedIn(context, ref)) return;
    setState(() => _sending = true);
    try {
      await _controller.add(body, parentId: _replyTo?.id);
      ref
          .read(postStoreProvider.notifier)
          .countComments(widget.postId, 1, base: widget.post);
      _text.clear();
      if (mounted) setState(() => _replyTo = null);
    } catch (e) {
      if (mounted) _snack(errorMessage(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _reply(Comment c) {
    if (!ensureSignedIn(context, ref)) return;
    // Replies are one level deep: a reply to a reply joins its thread.
    setState(() => _replyTo = c);
    _focus.requestFocus();
  }

  Future<void> _delete(Comment c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete comment?'),
        content: const Text('This removes it for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final removed = await _controller.delete(c.id);
      ref
          .read(postStoreProvider.notifier)
          .countComments(widget.postId, -removed, base: widget.post);
      if (mounted) _snack('Comment deleted');
    } catch (e) {
      if (mounted) _snack(errorMessage(e));
    }
  }

  Future<void> _report(Comment c) async {
    if (!ensureSignedIn(context, ref)) return;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report this comment?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Moderators will review it. Comments reported by several '
              'people are hidden until then.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLength: 300,
              decoration: const InputDecoration(labelText: 'Reason (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Report'),
          ),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (ok != true) return;
    try {
      await _controller.report(c.id, reason: text);
      if (mounted) _snack('Thanks, we\'ll take a look.');
    } catch (e) {
      if (mounted) _snack(errorMessage(e));
    }
  }

  Future<void> _block(Comment c, String kind) => changeBlock(
    context,
    ref,
    userId: c.author.id,
    name: c.author.displayName.isEmpty
        ? '@${c.author.handle}'
        : c.author.displayName,
    kind: kind,
  );

  @override
  Widget build(BuildContext context) {
    final comments = ref.watch(commentsProvider(widget.postId));
    final session = ref.watch(sessionProvider);
    return Scaffold(
      appBar: AppBar(
        leading: exitLeading(context),
        title: const Text('Comments'),
      ),
      body: Column(
        children: [
          Expanded(
            child: comments.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.invalidate(commentsProvider(widget.postId)),
              ),
              data: (state) => _list(state, session),
            ),
          ),
          const Divider(height: 1),
          _composer(session),
        ],
      ),
    );
  }

  Widget _list(CommentsState state, Session session) {
    final threads = state.threads;
    if (threads.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No comments yet. Start the conversation.'),
        ),
      );
    }
    final me = session.user?.id;
    bool canDelete(Comment c) =>
        session.signedIn && (c.author.id == me || session.isModerator);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final t in threads)
          ReadingWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CommentTile(
                  comment: t.comment,
                  canDelete: canDelete(t.comment),
                  onReply: () => _reply(t.comment),
                  onDelete: () => _delete(t.comment),
                  onReport: () => _report(t.comment),
                  isMine: t.comment.author.id == me,
                  onBlock: (kind) => _block(t.comment, kind),
                ),
                for (final r in t.replies)
                  Padding(
                    padding: const EdgeInsets.only(left: 40),
                    child: CommentTile(
                      comment: r,
                      canDelete: canDelete(r),
                      onReply: () => _reply(t.comment),
                      onDelete: () => _delete(r),
                      onReport: () => _report(r),
                      isMine: r.author.id == me,
                      onBlock: (kind) => _block(r, kind),
                    ),
                  ),
              ],
            ),
          ),
        if (state.hasMore)
          Center(
            child: TextButton(
              onPressed: state.loadingMore
                  ? null
                  : () => _controller.loadMore().catchError((Object e) {
                      if (mounted) _snack(errorMessage(e));
                    }),
              child: const Text('Load more comments'),
            ),
          ),
      ],
    );
  }

  Widget _composer(Session session) {
    if (!session.signedIn) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.tonal(
            onPressed: () => context.push('/signin'),
            child: const Text('Sign in to comment'),
          ),
        ),
      );
    }
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: ReadingWidth(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_replyTo != null)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Replying to ${_replyTo!.author.displayName}',
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cancel reply',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _replyTo = null),
                    ),
                  ],
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('comment-field'),
                      controller: _text,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 1000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: _replyTo == null
                            ? 'Add a comment'
                            : 'Write a reply',
                        counterText: '',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    style: amberIconButtonStyle,
                    tooltip: 'Send',
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CommentTile extends StatelessWidget {
  const CommentTile({
    super.key,
    required this.comment,
    required this.canDelete,
    required this.onReply,
    required this.onDelete,
    required this.onReport,
    this.isMine = false,
    this.onBlock,
  });

  final Comment comment;
  final bool canDelete;
  final VoidCallback onReply;
  final VoidCallback onDelete;
  final VoidCallback onReport;
  final bool isMine;

  /// Mutes (`mute`) or blocks (`block`) the author.
  final void Function(String kind)? onBlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = comment.author;
    final name = a.displayName.isEmpty ? '@${a.handle}' : a.displayName;
    return Padding(
      key: ValueKey('comment-${comment.id}'),
      padding: const EdgeInsets.fromLTRB(16, 6, 4, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            customBorder: const CircleBorder(),
            onTap: a.handle.isEmpty
                ? null
                : () => context.push('/users/${Uri.encodeComponent(a.handle)}'),
            child: PersonAvatar(name: name, radius: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(name, style: theme.textTheme.labelLarge),
                    if (a.handle.isNotEmpty)
                      Text('@${a.handle}', style: theme.textTheme.bodySmall),
                    Text(
                      timeAgo(comment.createdAt),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(comment.body),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(48, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: onReply,
                  child: const Text('Reply'),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert, size: 18),
            onSelected: (v) => switch (v) {
              'delete' => onDelete(),
              'report' => onReport(),
              _ => onBlock?.call(v),
            },
            itemBuilder: (_) => [
              if (canDelete)
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              if (!isMine) ...[
                const PopupMenuItem(value: 'report', child: Text('Report')),
                if (onBlock != null) ...[
                  PopupMenuItem(value: 'mute', child: Text('Mute $name')),
                  PopupMenuItem(value: 'block', child: Text('Block $name')),
                ],
              ],
            ],
          ),
        ],
      ),
    );
  }
}
