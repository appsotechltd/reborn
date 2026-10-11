import '../../theme.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../data/providers.dart';
import '../../layout/adaptive.dart';
import '../../widgets/common.dart';
import 'circles_screen.dart';

const kCircleFull = 'This circle is full (50 members).';

/// One book circle: details, join/leave, and its messages, refreshed every
/// [pollEvery] while the screen is open.
class CircleScreen extends ConsumerStatefulWidget {
  const CircleScreen({
    super.key,
    required this.circleId,
    this.pollEvery = const Duration(seconds: 10),
  });
  final String circleId;
  final Duration pollEvery;

  @override
  ConsumerState<CircleScreen> createState() => _CircleScreenState();
}

class _CircleScreenState extends ConsumerState<CircleScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  Circle? _circle;
  Object? _error;
  List<CircleMessage> _messages = const [];
  bool _busy = false;
  bool _sending = false;
  String? _full;
  IdeaCard? _attached;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(widget.pollEvery, (_) => _refreshMessages());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _load() async {
    try {
      final c = await ref.read(repositoryProvider).circle(widget.circleId);
      if (!mounted) return;
      setState(() {
        _circle = c;
        _error = null;
      });
      await _refreshMessages();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _refreshMessages() async {
    final c = _circle;
    if (c == null || !c.isMember || !mounted) return;
    try {
      final latest = await ref
          .read(repositoryProvider)
          .circleMessages(widget.circleId);
      if (!mounted) return;
      final byId = {for (final m in _messages) m.id: m};
      for (final m in latest) {
        byId[m.id] = m;
      }
      // Messages deleted elsewhere drop out of the latest window.
      final latestIds = latest.map((m) => m.id).toSet();
      final oldest = latest.isEmpty ? null : latest.first.createdAt;
      final merged =
          byId.values.where((m) {
            if (latestIds.contains(m.id)) return true;
            final t = m.createdAt;
            return oldest != null && t != null && t.isBefore(oldest);
          }).toList()..sort(
            (a, b) => (a.createdAt ?? DateTime(0)).compareTo(
              b.createdAt ?? DateTime(0),
            ),
          );
      final grew = merged.length > _messages.length;
      setState(() => _messages = merged);
      if (grew) _scrollToEnd();
    } catch (_) {
      // Try again on the next poll.
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _join() async {
    if (!ensureSignedIn(context, ref)) return;
    setState(() => _busy = true);
    try {
      final c = await ref.read(repositoryProvider).joinCircle(widget.circleId);
      if (!mounted) return;
      setState(() => _circle = c);
      ref.invalidate(circlesProvider);
      ref.invalidate(circleMembersProvider(widget.circleId));
      await _refreshMessages();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'circle_full') {
        setState(() => _full = kCircleFull);
        _snack(kCircleFull);
      } else {
        _snack(errorMessage(e));
      }
    } catch (e) {
      if (mounted) _snack(errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave this circle?'),
        content: Text(
          _circle?.isOwner ?? false
              ? 'The longest-standing member becomes the owner. If you are '
                    'the last one, the circle is deleted.'
              : 'You can join again later if there is room.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(repositoryProvider).leaveCircle(widget.circleId);
      ref.invalidate(circlesProvider);
      ref.invalidate(circleMembersProvider(widget.circleId));
      if (!mounted) return;
      setState(() => _messages = const []);
      try {
        final c = await ref.read(repositoryProvider).circle(widget.circleId);
        if (mounted) setState(() => _circle = c);
      } on ApiException catch (e) {
        // The circle was deleted when its last member left.
        if (e.statusCode == 404 && mounted) {
          if (Navigator.of(context).canPop()) {
            context.pop();
          } else {
            // In the side pane of Book circles: clear the pane.
            ref
                .read(paneSelectionProvider(CirclesScreen.pane).notifier)
                .select(null);
          }
        }
      }
    } catch (e) {
      if (mounted) _snack(errorMessage(e));
    }
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final m = await ref
          .read(repositoryProvider)
          .postCircleMessage(widget.circleId, body, postId: _attached?.id);
      if (!mounted) return;
      _text.clear();
      setState(() {
        _messages = [..._messages, m];
        _attached = null;
      });
      _scrollToEnd();
    } catch (e) {
      if (mounted) _snack(errorMessage(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(CircleMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
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
    if (ok != true || !mounted) return;
    try {
      await ref
          .read(repositoryProvider)
          .deleteCircleMessage(widget.circleId, m.id);
      if (mounted) {
        setState(
          () => _messages = _messages.where((x) => x.id != m.id).toList(),
        );
      }
    } catch (e) {
      if (mounted) _snack(errorMessage(e));
    }
  }

  void _showMembers(Circle c) {
    ref.invalidate(circleMembersProvider(c.id));
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _MembersSheet(circleId: c.id),
    );
  }

  Future<void> _attach(Circle c) async {
    final card = await showModalBottomSheet<IdeaCard>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _AttachIdeaSheet(sourceId: c.sourceId),
    );
    if (card != null && mounted) setState(() => _attached = card);
  }

  @override
  Widget build(BuildContext context) {
    final c = _circle;
    return Scaffold(
      appBar: AppBar(
        title: Text(c?.name ?? 'Circle'),
        actions: [
          if (c != null && c.isMember)
            IconButton(
              tooltip: 'Leave circle',
              icon: const Icon(Icons.logout),
              onPressed: _leave,
            ),
        ],
      ),
      body: c == null
          ? (_error != null
                ? ErrorView(error: _error!, onRetry: _load)
                : const LoadingView())
          : Column(
              children: [
                _header(c),
                const Divider(height: 1),
                Expanded(child: c.isMember ? _messageList(c) : _joinPrompt(c)),
                if (c.isMember) _composer(c),
              ],
            ),
    );
  }

  Widget _header(Circle c) {
    final theme = Theme.of(context);
    return ReadingWidth(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: c.sourceId.isEmpty
                  ? null
                  : () => context.push(
                      '/sources/${Uri.encodeComponent(c.sourceId)}',
                    ),
              child: Row(
                children: [
                  const Icon(Icons.menu_book_outlined, size: 16),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      c.sourceTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (c.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(c.description),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                InkWell(
                  onTap: () => _showMembers(c),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.group_outlined, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '${c.members} ${c.members == 1 ? 'member' : 'members'}',
                        key: const ValueKey('circle-members'),
                        style: TextStyle(color: theme.colorScheme.primary),
                      ),
                    ],
                  ),
                ),
                if (c.owner != null)
                  InkWell(
                    onTap: () => context.push(
                      '/users/${Uri.encodeComponent(c.owner!.handle)}',
                    ),
                    child: Text(
                      'Started by ${c.owner!.displayName}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                if (c.isMember)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(c.isOwner ? 'Owner' : 'Member'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _joinPrompt(Circle c) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.groups_outlined, size: 48),
          const SizedBox(height: 12),
          Text(
            _full ?? 'Join to read and post messages in this circle.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('join-circle'),
            onPressed: _busy || _full != null ? null : _join,
            child: const Text('Join circle'),
          ),
        ],
      ),
    ),
  );

  Widget _messageList(Circle c) {
    if (_messages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No messages yet. Say hello and share an idea.'),
        ),
      );
    }
    final session = ref.watch(sessionProvider);
    final titles = {
      for (final card
          in ref.watch(sourceProvider(c.sourceId)).value?.value.cards ??
              const <IdeaCard>[])
        card.id: card.title,
    };
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final m = _messages[i];
        final canDelete =
            m.author.id == session.user?.id || c.isOwner || session.isModerator;
        return ReadingWidth(
          child: _MessageTile(
            message: m,
            ideaTitle: m.postId == null ? null : titles[m.postId],
            onDelete: canDelete ? () => _delete(m) : null,
          ),
        );
      },
    );
  }

  Widget _composer(Circle c) => SafeArea(
    top: false,
    child: ReadingWidth(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_attached != null)
              InputChip(
                key: const ValueKey('attached-idea'),
                avatar: const Icon(Icons.lightbulb_outline, size: 18),
                label: Text(_attached!.title, overflow: TextOverflow.ellipsis),
                onDeleted: () => setState(() => _attached = null),
              ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Attach an idea from this book',
                  icon: const Icon(Icons.lightbulb_outline),
                  onPressed: () => _attach(c),
                ),
                Expanded(
                  child: TextField(
                    key: const ValueKey('circle-message-field'),
                    controller: _text,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 2000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Message the circle',
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
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message, this.ideaTitle, this.onDelete});
  final CircleMessage message;
  final String? ideaTitle;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = message;
    final name = m.author.displayName.isEmpty
        ? '@${m.author.handle}'
        : m.author.displayName;
    return Padding(
      key: ValueKey('message-${m.id}'),
      padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            customBorder: const CircleBorder(),
            onTap: m.author.handle.isEmpty
                ? null
                : () => context.push(
                    '/users/${Uri.encodeComponent(m.author.handle)}',
                  ),
            child: PersonAvatar(name: name, radius: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  children: [
                    Text(name, style: theme.textTheme.labelLarge),
                    Text(
                      timeAgo(m.createdAt),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(m.body),
                if (m.postId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: ActionChip(
                      key: ValueKey('message-idea-${m.id}'),
                      avatar: const Icon(Icons.lightbulb_outline, size: 18),
                      label: Text(ideaTitle ?? 'Open the idea'),
                      onPressed: () => context.push(
                        '/cards/${Uri.encodeComponent(m.postId!)}',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: 'Delete message',
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

/// Picks an idea from the circle's book.
class _AttachIdeaSheet extends ConsumerWidget {
  const _AttachIdeaSheet({required this.sourceId});
  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(sourceProvider(sourceId));
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: source.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(
            error: e,
            onRetry: () => ref.invalidate(sourceProvider(sourceId)),
          ),
          data: (f) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Attach an idea from ${f.value.source.title}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final card in f.value.cards)
                ListTile(
                  title: Text(card.title),
                  onTap: () => Navigator.pop(context, card),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The circle's members, owner first; tapping one opens their profile.
class _MembersSheet extends ConsumerWidget {
  const _MembersSheet({required this.circleId});
  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(circleMembersProvider(circleId));
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: members.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(
            error: e,
            onRetry: () => ref.invalidate(circleMembersProvider(circleId)),
          ),
          data: (list) => ListView(
            key: const ValueKey('circle-member-list'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Members',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (list.isEmpty) const ListTile(title: Text('No members yet')),
              for (final m in list)
                ListTile(
                  key: ValueKey('member-${m.id}'),
                  leading: PersonAvatar(name: m.name),
                  title: Text(m.name),
                  subtitle: Text(
                    m.joinedAt == null
                        ? '@${m.handle}'
                        : '@${m.handle} · joined ${timeAgo(m.joinedAt)}',
                  ),
                  trailing: m.isOwner
                      ? const Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text('Owner'),
                        )
                      : null,
                  onTap: m.handle.isEmpty
                      ? null
                      : () {
                          final router = GoRouter.of(context);
                          Navigator.pop(context);
                          router.push(
                            '/users/${Uri.encodeComponent(m.handle)}',
                          );
                        },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
