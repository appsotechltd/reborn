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
        data: (f) => f.value.cards.isEmpty
            ? const Center(
                child: Text(
                  'This stash is empty. Tap Stash on any idea to add it.',
                ),
              )
            : ListView.separated(
                itemCount: f.value.cards.length,
                separatorBuilder: (_, _) =>
                    const ReadingWidth(child: Divider(height: 1)),
                itemBuilder: (context, i) {
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
