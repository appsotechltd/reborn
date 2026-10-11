import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../widgets/common.dart';

/// Someone's public stash (GET /v1/public/stashes/{id}).
class PublicStashScreen extends ConsumerWidget {
  const PublicStashScreen({super.key, required this.stashId});
  final String stashId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stash = ref.watch(publicStashProvider(stashId));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: exitLeading(context),
        title: Text(stash.value?.stash.name ?? 'Stash'),
      ),
      body: stash.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(publicStashProvider(stashId)),
        ),
        data: (s) => ListView(
          children: [
            ReadingWidth(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.stash.name, style: theme.textTheme.headlineSmall),
                    if (s.stash.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(s.stash.description),
                    ],
                    if (s.owner != null)
                      TextButton.icon(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                        onPressed: () => context.push(
                          '/users/${Uri.encodeComponent(s.owner!.handle)}',
                        ),
                        icon: const Icon(Icons.person_outline, size: 18),
                        label: Text(
                          'By ${s.owner!.displayName} (@${s.owner!.handle})',
                        ),
                      ),
                    Text(
                      '${s.cards.length} '
                      '${s.cards.length == 1 ? 'idea' : 'ideas'}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            for (final c in s.cards) ReadingWidth(child: CardTile(card: c)),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
