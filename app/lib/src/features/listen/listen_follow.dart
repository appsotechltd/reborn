import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'listen_controller.dart';

/// Keeps Listen mode on this screen's audio. While Listen mode is on,
/// opening the screen (or moving to another item on it, a new [target])
/// switches Listen mode to [target] (see [ListenController.follow]).
/// Screens without audio of their own don't use this, so Listen mode carries
/// on there.
///
/// Coming back to the screen (closing the player or a page on top of it)
/// follows again only when Listen mode has moved to other audio since: not
/// when it is still the session this screen left, or this screen's own list,
/// so closing the player never pulls it back a card.
/// A null [target] (nothing loaded yet) follows nothing.
class ListenFollow extends ConsumerStatefulWidget {
  const ListenFollow({super.key, required this.target, required this.child});

  final ListenTarget? target;
  final Widget child;

  @override
  ConsumerState<ListenFollow> createState() => _ListenFollowState();
}

class _ListenFollowState extends ConsumerState<ListenFollow> {
  /// On screen (not covered by another page, nor in a hidden tab).
  bool _visible = false;

  /// The Listen session this screen last followed into, or left alone.
  int? _session;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible == _visible) return;
    _visible = visible;
    if (!visible) return;
    if (_session != null) {
      // Back on screen: follow only if Listen mode moved on to other audio.
      final s = ref.read(listenProvider);
      final target = widget.target;
      if (s.session == _session ||
          (target != null &&
              target.cardId == null &&
              s.queueKey == target.key)) {
        return;
      }
    }
    _follow();
  }

  @override
  void didUpdateWidget(ListenFollow old) {
    super.didUpdateWidget(old);
    if (_visible && old.target?.identity != widget.target?.identity) {
      _follow();
    }
  }

  void _follow() {
    if (widget.target == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final target = widget.target;
      if (!mounted || !_visible || target == null) return;
      await ref.read(listenProvider.notifier).follow(target);
      if (mounted) _session = ref.read(listenProvider).session;
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
