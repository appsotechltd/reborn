import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import 'notifications_controller.dart';

/// Bell with the unread count; opens the inbox. Hidden when signed out.
class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({super.key});

  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (ref.read(sessionProvider).signedIn) {
          ref.invalidate(notificationsProvider);
        }
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(sessionProvider.select((s) => s.signedIn));
    if (!signedIn) return const SizedBox.shrink();
    final unread = ref.watch(unreadCountProvider);
    return IconButton(
      key: const ValueKey('notification-bell'),
      tooltip: unread == 0 ? 'Notifications' : 'Notifications, $unread unread',
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: Icon(
          unread > 0 ? Icons.notifications : Icons.notifications_none,
        ),
      ),
    );
  }
}

/// The inbox: newest first; tapping an item marks it read and opens it.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  static IconData _icon(String kind) => switch (kind) {
    'reply' => Icons.mode_comment_outlined,
    'follow' => Icons.person_add_alt,
    'circle' => Icons.groups_outlined,
    'reward' => Icons.workspace_premium_outlined,
    _ => Icons.wb_sunny_outlined,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(sessionProvider.select((s) => s.signedIn));
    if (!signedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: const SignInPrompt(
          icon: Icons.notifications_none,
          title: 'Notifications',
          message: 'Sign in to hear about replies, follows and your circles.',
        ),
      );
    }
    final page = ref.watch(notificationsProvider);
    final controller = ref.read(notificationsProvider.notifier);
    final hasUnread = (page.value?.items ?? const []).any((n) => !n.read);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: controller.markAllRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: page.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(notificationsProvider),
        ),
        data: (p) => RefreshIndicator(
          onRefresh: () => ref.refresh(notificationsProvider.future),
          child: p.items.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        "You're all caught up. Replies, follows and circle "
                        'messages show up here.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: p.items.length,
                  itemBuilder: (context, i) => ReadingWidth(
                    child: _NotificationTile(
                      item: p.items[i],
                      icon: _icon(p.items[i].kind),
                      onTap: () {
                        final n = p.items[i];
                        controller.markRead([n.id]);
                        final loc = notificationLocation(
                          postId: n.postId,
                          commentId: n.commentId,
                          circleId: n.circleId,
                          actorHandle: n.actor?.handle,
                        );
                        if (loc != null) context.push(loc);
                      },
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.icon,
    required this.onTap,
  });
  final AppNotification item;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unread = !item.read;
    return ListTile(
      key: ValueKey('notification-${item.id}'),
      tileColor: unread
          ? scheme.primaryContainer.withValues(alpha: 0.35)
          : null,
      leading: CircleAvatar(
        backgroundColor: unread
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest,
        child: Icon(icon, size: 20),
      ),
      title: Text(
        item.text,
        style: unread ? const TextStyle(fontWeight: FontWeight.w600) : null,
      ),
      subtitle: Text(timeAgo(item.createdAt)),
      trailing: unread
          ? Container(
              key: const ValueKey('unread-dot'),
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}
