import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../widgets/common.dart';
import 'stashes_screen.dart';

class StashDetailScreen extends ConsumerWidget {
  const StashDetailScreen({super.key, required this.stashId});
  final String stashId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(stashDetailProvider(stashId));
    final f = detail.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(f?.value.stash.name ?? 'Stash'),
        actions: [
          if (f != null && !f.offline)
            StashMenu(
              stash: f.value.stash,
              onDeleted: () {
                if (context.mounted) context.pop();
              },
            ),
        ],
      ),
      body: detail.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(stashDetailProvider(stashId)),
        ),
        data: (f) => ListView.separated(
          itemCount: f.value.cards.length + 1,
          separatorBuilder: (_, _) =>
              const ReadingWidth(child: Divider(height: 1)),
          itemBuilder: (context, index) {
            if (index == 0) {
              return ReadingWidth(
                child: Column(
                  children: [
                    _PublicToggle(
                      stashId: stashId,
                      isPublic: f.value.stash.isPublic,
                      enabled: !f.offline,
                    ),
                    if (f.value.cards.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'This stash is empty. Tap Stash on any idea '
                          'to add it.',
                        ),
                      ),
                  ],
                ),
              );
            }
            final i = index - 1;
            final card = f.value.cards[i];
            return ReadingWidth(
              child: CardTile(
                card: card,
                trailing: f.offline
                    ? null
                    : IconButton(
                        tooltip: 'Remove from stash',
                        icon: const Icon(Icons.bookmark_remove_outlined),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await ref
                                .read(repositoryProvider)
                                .removeFromStash(stashId, card.id);
                            ref.invalidate(stashDetailProvider(stashId));
                            ref.invalidate(stashesProvider);
                          } catch (e) {
                            messenger.showSnackBar(
                              SnackBar(content: Text(errorMessage(e))),
                            );
                          }
                        },
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// "Public" switch: public stashes show on your profile.
class _PublicToggle extends ConsumerStatefulWidget {
  const _PublicToggle({
    required this.stashId,
    required this.isPublic,
    required this.enabled,
  });
  final String stashId;
  final bool isPublic;
  final bool enabled;

  @override
  ConsumerState<_PublicToggle> createState() => _PublicToggleState();
}

class _PublicToggleState extends ConsumerState<_PublicToggle> {
  late bool _on = widget.isPublic;
  bool _busy = false;

  @override
  void didUpdateWidget(_PublicToggle old) {
    super.didUpdateWidget(old);
    if (old.isPublic != widget.isPublic) _on = widget.isPublic;
  }

  Future<void> _set(bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _on = on;
      _busy = true;
    });
    try {
      await ref.read(repositoryProvider).setStashPublic(widget.stashId, on);
      ref
        ..invalidate(stashDetailProvider(widget.stashId))
        ..invalidate(stashesProvider);
    } catch (e) {
      if (mounted) setState(() => _on = !on);
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    key: const ValueKey('stash-public'),
    secondary: Icon(_on ? Icons.public : Icons.lock_outline),
    title: const Text('Public'),
    subtitle: Text(
      _on
          ? 'Shown on your profile for anyone to see'
          : 'Only you can see this stash',
    ),
    value: _on,
    onChanged: widget.enabled && !_busy ? _set : null,
  );
}
