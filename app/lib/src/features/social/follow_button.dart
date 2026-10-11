import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';

/// Follow / Following toggle for a user, source or author, updated
/// optimistically. With [showCount] it also shows the follower count.
class FollowButton extends ConsumerStatefulWidget {
  const FollowButton({
    super.key,
    required this.kind,
    required this.target,
    required this.initial,
    this.showCount = true,
    this.onChanged,
  });

  final FollowKind kind;

  /// User id, source id or author name.
  final String target;
  final FollowState initial;
  final bool showCount;
  final ValueChanged<FollowState>? onChanged;

  @override
  ConsumerState<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<FollowButton> {
  late FollowState _state = widget.initial;
  bool _busy = false;

  @override
  void didUpdateWidget(FollowButton old) {
    super.didUpdateWidget(old);
    if (old.initial.isFollowing != widget.initial.isFollowing ||
        old.initial.followers != widget.initial.followers ||
        old.target != widget.target) {
      _state = widget.initial;
    }
  }

  Future<void> _toggle() async {
    if (_busy || !ensureSignedIn(context, ref)) return;
    final before = _state;
    final on = !before.isFollowing;
    setState(() {
      _busy = true;
      _state = FollowState(
        followers: (before.followers + (on ? 1 : -1)).clamp(0, 1 << 30),
        isFollowing: on,
      );
    });
    try {
      final after = await ref
          .read(repositoryProvider)
          .setFollow(widget.kind, widget.target, on);
      if (!mounted) return;
      setState(() => _state = after);
      widget.onChanged?.call(after);
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = before);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(errorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final following = _state.isFollowing;
    final button = following
        ? OutlinedButton.icon(
            key: const ValueKey('follow-button'),
            onPressed: _toggle,
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Following'),
          )
        : FilledButton.icon(
            key: const ValueKey('follow-button'),
            onPressed: _toggle,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Follow'),
          );
    if (!widget.showCount) return button;
    final n = _state.followers;
    return Wrap(
      spacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        button,
        Text(
          '${compactCount(n)} ${n == 1 ? 'follower' : 'followers'}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
