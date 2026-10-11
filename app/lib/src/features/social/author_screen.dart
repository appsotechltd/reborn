import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import 'follow_button.dart';

/// An author: their sources in the library, and a follow button.
class AuthorScreen extends ConsumerWidget {
  const AuthorScreen({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final author = ref.watch(authorProvider(name));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Author')),
      body: author.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(authorProvider(name)),
        ),
        data: (a) => ListView(
          children: [
            ReadingWidth(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AUTHOR',
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(a.name, style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 12),
                    FollowButton(
                      kind: FollowKind.author,
                      target: a.name,
                      initial: a.follow,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Follow to see new ideas from their work in your '
                      'timeline.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${a.sources.length} '
                      '${a.sources.length == 1 ? 'source' : 'sources'} '
                      'in the library',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
            for (final s in a.sources)
              ReadingWidth(
                child: ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(s.title),
                  subtitle: Text(
                    '${s.cardCount} ${s.cardCount == 1 ? 'idea' : 'ideas'}'
                    '${s.kind.isEmpty ? '' : ' · ${s.kind}'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      context.push('/sources/${Uri.encodeComponent(s.id)}'),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
