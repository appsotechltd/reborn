import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Lets the user choose (or create) a stash for [card].
Future<void> showStashPicker(
  BuildContext context,
  WidgetRef ref,
  IdeaCard card,
) async {
  if (!await requireSignIn(
    context,
    ref,
    'Sign in to stash ideas and review them later.',
  )) {
    return;
  }
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final name = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _StashPickerSheet(card: card),
  );
  if (name != null) {
    messenger.showSnackBar(SnackBar(content: Text('Stashed in “$name”')));
  }
}

class _StashPickerSheet extends ConsumerStatefulWidget {
  const _StashPickerSheet({required this.card});
  final IdeaCard card;

  @override
  ConsumerState<_StashPickerSheet> createState() => _StashPickerSheetState();
}

class _StashPickerSheetState extends ConsumerState<_StashPickerSheet> {
  final _newName = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  Future<void> _add(Stash stash) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(repositoryProvider).addToStash(stash.id, widget.card);
      ref.invalidate(stashesProvider);
      ref.invalidate(stashDetailProvider(stash.id));
      if (mounted) Navigator.pop(context, stash.name);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = errorMessage(e);
      });
    }
  }

  Future<void> _create() async {
    final name = _newName.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final stash = await ref.read(repositoryProvider).createStash(name);
      await _add(stash);
    } catch (e) {
      setState(() {
        _busy = false;
        _error = errorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final stashes = ref.watch(stashesProvider);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        // Sized to its content (an Align would take the sheet's full
        // height, leaving it mostly blank).
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kReadingWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    'Stash this idea',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                Flexible(
                  child: stashes.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(24),
                      child: LoadingView(),
                    ),
                    error: (e, _) => ErrorView(error: e),
                    data: (f) => ListView(
                      shrinkWrap: true,
                      children: [
                        if (f.value.isEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                            child: Text(
                              'Stashes are folders for ideas you want to keep '
                              'and review. Name your first one below.',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        for (final s in f.value)
                          ListTile(
                            leading: const Icon(Icons.bookmarks_outlined),
                            title: Text(s.name),
                            subtitle: Text('${s.cardCount} ideas'),
                            enabled: !_busy,
                            onTap: () => _add(s),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newName,
                          decoration: const InputDecoration(
                            labelText: 'New stash',
                            hintText: 'e.g. Morning reads',
                            isDense: true,
                          ),
                          onSubmitted: (_) => _create(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _busy ? null : _create,
                        child: const Text('Create'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
