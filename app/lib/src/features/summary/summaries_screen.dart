import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../widgets/common.dart';
import 'summary_controller.dart';
import 'summary_widgets.dart';

/// Every summary: topics (the best ideas on one subject from several books)
/// first, then every book with five or more ideas.
class SummariesScreen extends ConsumerWidget {
  const SummariesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(summariesProvider);
    final theme = Theme.of(context);
    Widget heading(String title, String sub) => ReadingWidth(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(sub, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        leading: exitLeading(context),
        title: const Text('Summaries'),
      ),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(summariesProvider),
        ),
        data: (f) {
          final topics = f.value.summaries.where((s) => !s.isBook).toList();
          final books = f.value.summaries.where((s) => s.isBook).toList();
          final items = <Widget>[
            if (topics.isNotEmpty)
              heading(
                'Topics',
                'The best ideas on one subject, from several books.',
              ),
            for (final s in topics) _item(s),
            if (books.isNotEmpty)
              heading(
                'Books',
                'Every book with five or more ideas, from start to finish.',
              ),
            for (final s in books) _item(s),
          ];
          return RefreshIndicator(
            onRefresh: () => ref.refresh(summariesProvider.future),
            child: ListView(
              key: const ValueKey('summaries-list'),
              padding: const EdgeInsets.only(bottom: 24),
              children: items,
            ),
          );
        },
      ),
    );
  }

  Widget _item(Summary summary) => ReadingWidth(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: SummaryPostCard(summary: summary),
    ),
  );
}
