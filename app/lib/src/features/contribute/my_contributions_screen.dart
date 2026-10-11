import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../widgets/common.dart';
import 'contribution_tile.dart';

class MyContributionsScreen extends ConsumerWidget {
  const MyContributionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(sessionProvider.select((s) => s.signedIn));
    return Scaffold(
      appBar: AppBar(
        leading: exitLeading(context),
        title: const Text('My contributions'),
      ),
      floatingActionButton: signedIn
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/contribute'),
              icon: const Icon(Icons.add),
              label: const Text('New idea'),
            )
          : null,
      body: !signedIn
          ? const SignInPrompt(
              icon: Icons.inbox_outlined,
              title: 'Your contributions',
              message: 'Sign in to see ideas you have submitted.',
            )
          : ref
                .watch(myContributionsProvider)
                .when(
                  loading: () => const LoadingView(),
                  error: (e, _) => ErrorView(
                    error: e,
                    onRetry: () => ref.invalidate(myContributionsProvider),
                  ),
                  data: (list) => list.isEmpty
                      ? const Center(child: Text('Nothing submitted yet.'))
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 96),
                          children: [
                            for (final c in list)
                              ReadingWidth(
                                child: ExpansionTile(
                                  title: Text(c.title),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        StatusChip(status: c.status),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            c.source.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  childrenPadding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    16,
                                  ),
                                  expandedCrossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    ContributionDetails(c: c),
                                    if (c.cardId != null)
                                      TextButton(
                                        onPressed: () => context.push(
                                          '/cards/${Uri.encodeComponent(c.cardId!)}',
                                        ),
                                        child: const Text(
                                          'View published card',
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
    );
  }
}
