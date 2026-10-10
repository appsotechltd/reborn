import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';

/// Asks for a stash name (create or rename). Returns null if cancelled.
Future<String?> askStashName(
  BuildContext context, {
  String? initial,
  required String title,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  ).then((v) => (v == null || v.isEmpty) ? null : v);
}

class StashesScreen extends ConsumerWidget {
  const StashesScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await askStashName(context, title: 'New stash');
    if (name == null) return;
    try {
      await ref.read(repositoryProvider).createStash(name);
      ref.invalidate(stashesProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(sessionProvider.select((s) => s.signedIn));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stashes'),
        actions: const [ProfileMenuButton(), SizedBox(width: 8)],
      ),
      floatingActionButton: signedIn
          ? FloatingActionButton.extended(
              onPressed: () => _create(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('New stash'),
            )
          : null,
      body: !signedIn
          ? const SignInPrompt(
              icon: Icons.bookmarks_outlined,
              title: 'Keep the ideas you love',
              message: 'Sign in to stash ideas into collections. Stashed ideas are saved for offline reading.',
            )
          : ref
                .watch(stashesProvider)
                .when(
                  loading: () => const LoadingView(),
                  error: (e, _) => ErrorView(
                    error: e,
                    onRetry: () => ref.invalidate(stashesProvider),
                  ),
                  data: (f) => f.value.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No stashes yet. Tap Stash on any idea, or create one here.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: () => ref.refresh(stashesProvider.future),
                          child: ListView(
                            padding: const EdgeInsets.only(bottom: 96),
                            children: [
                              for (final s in f.value)
                                ReadingWidth(
                                  child: _StashTile(
                                    stash: s,
                                    offline: f.offline,
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
    );
  }
}

class _StashTile extends ConsumerWidget {
  const _StashTile({required this.stash, required this.offline});
  final Stash stash;
  final bool offline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const CircleAvatar(
        child: Icon(Icons.bookmarks_outlined, size: 20),
      ),
      title: Text(stash.name),
      subtitle: Text(
        '${stash.cardCount} ${stash.cardCount == 1 ? 'idea' : 'ideas'}${stash.description.isEmpty ? '' : ' · ${stash.description}'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => context.push('/stashes/${stash.id}'),
      trailing: offline ? null : StashMenu(stash: stash),
    );
  }
}

/// Rename / delete menu for a stash.
class StashMenu extends ConsumerWidget {
  const StashMenu({super.key, required this.stash, this.onDeleted});
  final Stash stash;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Stash options',
      onSelected: (v) async {
        final messenger = ScaffoldMessenger.of(context);
        final repo = ref.read(repositoryProvider);
        try {
          if (v == 'rename') {
            final name = await askStashName(
              context,
              initial: stash.name,
              title: 'Rename stash',
            );
            if (name == null) return;
            await repo.renameStash(stash.id, name);
          } else if (v == 'delete') {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('Delete “${stash.name}”?'),
                content: const Text(
                  'The ideas stay in the library; only this stash is removed.',
                ),
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
            if (ok != true) return;
            await repo.deleteStash(stash.id);
            onDeleted?.call();
          }
          ref.invalidate(stashesProvider);
          ref.invalidate(stashDetailProvider(stash.id));
        } catch (e) {
          messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'rename', child: Text('Rename')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }
}
