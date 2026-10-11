import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../data/providers.dart';

/// The inbox. Empty when signed out.
class NotificationsController extends AsyncNotifier<NotificationsPage> {
  @override
  Future<NotificationsPage> build() async {
    final signedIn = ref.watch(sessionProvider.select((s) => s.signedIn));
    if (!signedIn) return const NotificationsPage(items: []);
    return ref.read(repositoryProvider).notifications();
  }

  /// Marks [ids] read now (optimistically) and on the server.
  Future<void> markRead(List<String> ids) async {
    final current = state.value;
    if (current == null) return;
    final unreadIds = {
      for (final n in current.items)
        if (!n.read && ids.contains(n.id)) n.id,
    };
    if (unreadIds.isEmpty) return;
    final now = DateTime.now();
    state = AsyncData(
      NotificationsPage(
        items: [
          for (final n in current.items)
            unreadIds.contains(n.id) ? n.markedRead(now) : n,
        ],
        unread: (current.unread - unreadIds.length).clamp(0, 1 << 30),
      ),
    );
    try {
      await ref
          .read(repositoryProvider)
          .markNotificationsRead(unreadIds.toList());
    } catch (_) {
      // The next refresh shows the server's state.
    }
  }

  Future<void> markAllRead() async {
    final current = state.value;
    if (current == null) return;
    final now = DateTime.now();
    state = AsyncData(
      NotificationsPage(
        items: [for (final n in current.items) n.markedRead(now)],
      ),
    );
    try {
      await ref.read(repositoryProvider).markNotificationsRead();
    } catch (_) {}
  }
}

final notificationsProvider =
    AsyncNotifierProvider<NotificationsController, NotificationsPage>(
      NotificationsController.new,
    );

final unreadCountProvider = Provider<int>(
  (ref) => ref.watch(notificationsProvider).value?.unread ?? 0,
);
