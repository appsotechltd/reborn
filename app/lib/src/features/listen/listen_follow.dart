import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
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
///
/// The other way round, when the audio moves on to another card (the next
/// one, or one picked in the player) while the screen is on show, [onMove]
/// shows it: the screen opens that card or turns to it. With [catchUp], it
/// also does so on coming back to the screen after the audio moved on in
/// the same session.
class ListenFollow extends ConsumerStatefulWidget {
  const ListenFollow({
    super.key,
    required this.target,
    required this.child,
    this.onMove,
    this.catchUp = true,
  });

  final ListenTarget? target;
  final Widget child;
  final void Function(Post post)? onMove;
  final bool catchUp;

  @override
  ConsumerState<ListenFollow> createState() => _ListenFollowState();
}

class _ListenFollowState extends ConsumerState<ListenFollow> {
  /// On screen (not covered by another page, nor in a hidden tab).
  bool _visible = false;

  /// The Listen session this screen last followed into, or left alone.
  int? _session;

  /// The session and post playing when the screen went out of sight.
  int? _leftSession;
  String? _leftPost;

  /// On show and on top (not under a page being pushed over it).
  bool get _onShow => _visible && (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible == _visible) return;
    _visible = visible;
    if (!visible) {
      final s = ref.read(listenProvider);
      _leftSession = s.active ? s.session : null;
      _leftPost = s.current?.id;
      return;
    }
    if (_catchUp()) return;
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

  /// Back on screen after the audio moved on within the session it left:
  /// shows the card playing now.
  bool _catchUp() {
    final s = ref.read(listenProvider);
    final post = s.current;
    if (!widget.catchUp ||
        widget.onMove == null ||
        post == null ||
        _leftSession != s.session ||
        _leftPost == post.id) {
      return false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _onShow) widget.onMove?.call(post);
    });
    return true;
  }

  void _moved(ListenState? before, ListenState now) {
    final post = now.current;
    if (before == null ||
        widget.onMove == null ||
        post == null ||
        !now.active ||
        now.session != before.session ||
        post.id == before.current?.id ||
        !_onShow) {
      return;
    }
    widget.onMove!(post);
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
  Widget build(BuildContext context) {
    ref.listen(listenProvider, _moved);
    return widget.child;
  }
}
