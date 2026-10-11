import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../layout/adaptive.dart';
import '../../widgets/common.dart';
import '../card/card_screen.dart';
import '../circles/circle_screen.dart';
import '../comments/comments_screen.dart';
import '../social/user_profile_screen.dart';
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

/// The inbox: newest first; tapping an item marks it read and opens it (on
/// the right, on expanded windows).
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  static const pane = 'notifications';

  /// What a notification opens, for the side pane; null if nothing.
  static Widget? detailFor(AppNotification n) {
    final circle = n.circleId;
    final post = n.postId;
    final handle = n.actor?.handle;
    if (circle != null && circle.isNotEmpty) {
      return CircleScreen(circleId: circle);
    }
    if (post != null && post.isNotEmpty) {
      final comment = n.commentId;
      return comment != null && comment.isNotEmpty
          ? CommentsScreen(postId: post)
          : CardScreen(cardId: post);
    }
    if (handle != null && handle.isNotEmpty) {
      return UserProfileScreen(handle: handle);
    }
    return null;
  }

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
    final twoPane = WindowSize.of(context).isTwoPane;
    final selection = paneSelectionProvider(pane);
    final selected = ref.watch(selection);
    final open = selected is AppNotification ? selected : null;
    final detail = open == null ? null : detailFor(open);
    return ListDetail(
      selectedId: detail == null ? null : open!.id,
      detail: () => detail!,
      empty: const EmptyDetail(
        icon: Icons.notifications_none,
        text: 'Pick a notification to open it here.',
      ),
      list: Scaffold(
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
                        selected: twoPane && open?.id == p.items[i].id,
                        onTap: () {
                          final n = p.items[i];
                          controller.markRead([n.id]);
                          if (twoPane && detailFor(n) != null) {
                            ref.read(selection.notifier).select(n);
                            return;
                          }
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
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.icon,
    required this.onTap,
    this.selected = false,
  });
  final AppNotification item;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final unread = !item.read;
    return ListTile(
      key: ValueKey('notification-${item.id}'),
      selected: selected,
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
