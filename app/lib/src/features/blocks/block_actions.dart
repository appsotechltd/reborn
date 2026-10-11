import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../comments/comments_controller.dart';
import '../notifications/notifications_controller.dart';

/// Blocks (`block`), mutes (`mute`) or, with null, unblocks [userId].
/// Blocking asks first. Returns true when it changed.
Future<bool> changeBlock(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String name,
  required String? kind,
}) async {
  if (!ensureSignedIn(context, ref)) return false;
  if (kind == 'block') {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Block $name?'),
        content: const Text(
          "You won't see each other's comments, circle messages or "
          'notifications, and any follows between you are removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
  }
  if (!context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(repositoryProvider).setBlock(userId, kind);
    ref
      ..invalidate(blocksProvider)
      ..invalidate(commentsProvider)
      ..invalidate(notificationsProvider)
      ..invalidate(followingProvider)
      ..invalidate(profileProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (kind) {
          'block' => 'Blocked $name',
          'mute' => 'Muted $name',
          _ => 'Unblocked $name',
        }),
      ),
    );
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    return false;
  }
}

/// Overflow menu on a profile: mute, block, or undo.
class BlockMenu extends ConsumerWidget {
  const BlockMenu({super.key, required this.userId, required this.name});
  final String userId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(sessionProvider.select((s) => s.signedIn));
    final current = signedIn
        ? ref
              .watch(blocksProvider)
              .value
              ?.where((b) => b.user.id == userId)
              .firstOrNull
              ?.kind
        : null;
    return PopupMenuButton<String>(
      key: const ValueKey('block-menu'),
      tooltip: 'More',
      onSelected: (v) => changeBlock(
        context,
        ref,
        userId: userId,
        name: name,
        kind: v == 'clear' ? null : v,
      ),
      itemBuilder: (_) => [
        if (current == null) ...[
          PopupMenuItem(value: 'mute', child: Text('Mute $name')),
          PopupMenuItem(value: 'block', child: Text('Block $name')),
        ] else if (current == 'mute') ...[
          PopupMenuItem(value: 'clear', child: Text('Unmute $name')),
          PopupMenuItem(value: 'block', child: Text('Block $name')),
        ] else
          PopupMenuItem(value: 'clear', child: Text('Unblock $name')),
      ],
    );
  }
}

/// Blocked and muted people, each with an undo button (in Settings).
class BlockedList extends ConsumerWidget {
  const BlockedList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocks = ref.watch(blocksProvider);
    return blocks.when(
      loading: () =>
          const Padding(padding: EdgeInsets.all(16), child: LoadingView()),
      error: (e, _) =>
          ErrorView(error: e, onRetry: () => ref.invalidate(blocksProvider)),
      data: (list) => list.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text("You haven't blocked or muted anyone."),
            )
          : Column(
              children: [
                for (final b in list)
                  ListTile(
                    key: ValueKey('blocked-${b.user.id}'),
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      b.muted ? Icons.volume_off_outlined : Icons.block,
                    ),
                    title: Text(
                      b.user.displayName.isEmpty
                          ? '@${b.user.handle}'
                          : b.user.displayName,
                    ),
                    subtitle: Text(
                      '@${b.user.handle} · ${b.muted ? 'Muted' : 'Blocked'}',
                    ),
                    trailing: TextButton(
                      onPressed: () => changeBlock(
                        context,
                        ref,
                        userId: b.user.id,
                        name: b.user.displayName.isEmpty
                            ? '@${b.user.handle}'
                            : b.user.displayName,
                        kind: null,
                      ),
                      child: const Text('Undo'),
                    ),
                  ),
              ],
            ),
    );
  }
}
