import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/member_models.dart';
import '../../api/models.dart';
import '../../data/providers.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../stashes/stashes_screen.dart';

/// The cards I write, filtered by my own categories, with a way to manage
/// the categories. Each card opens its editor and card studio.
class MyCardsScreen extends ConsumerStatefulWidget {
  const MyCardsScreen({super.key});

  @override
  ConsumerState<MyCardsScreen> createState() => _MyCardsScreenState();
}

class _MyCardsScreenState extends ConsumerState<MyCardsScreen> {
  /// '' for all cards, `none` for uncategorised, else a category id.
  String _category = '';

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(sessionProvider.select((s) => s.signedIn));
    return Scaffold(
      appBar: AppBar(
        leading: exitLeading(context),
        title: const Text('My cards'),
        actions: [
          if (signedIn) ...[
            IconButton(
              key: const ValueKey('my-cards-categories'),
              tooltip: 'Categories',
              icon: const Icon(Icons.folder_outlined),
              onPressed: () => showCategoriesSheet(context),
            ),
            IconButton(
              key: const ValueKey('my-cards-earnings'),
              tooltip: 'Earnings',
              icon: const Icon(Icons.savings_outlined),
              onPressed: () => context.push('/me/earnings'),
            ),
          ],
        ],
      ),
      floatingActionButton: signedIn
          ? FloatingActionButton.extended(
              key: const ValueKey('new-card'),
              onPressed: () => context.push('/me/cards/new'),
              icon: const Icon(Icons.add),
              label: const Text('New card'),
            )
          : null,
      body: !signedIn
          ? const SignInPrompt(
              icon: Icons.edit_note,
              title: 'Write your own cards',
              message:
                  'Sign in to share ideas in your own words with the people '
                  'who follow you.',
            )
          : RefreshIndicator(
              onRefresh: () => Future.wait([
                ref.refresh(myCardsProvider(_category).future),
                ref.refresh(myCategoriesProvider.future),
              ]),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  ReadingWidth(child: _filters()),
                  ..._cards(),
                ],
              ),
            ),
    );
  }

  Widget _filters() {
    final cats = ref.watch(myCategoriesProvider).value ?? const [];
    Widget chip(String id, String label) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        key: ValueKey('category-chip-${id.isEmpty ? 'all' : id}'),
        label: Text(label),
        selected: _category == id,
        onSelected: (_) => setState(() => _category = id),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          chip('', 'All'),
          for (final c in cats)
            chip(
              c.id,
              c.cardCount == null ? c.name : '${c.name} · ${c.cardCount}',
            ),
          if (cats.isNotEmpty) chip('none', 'No category'),
        ],
      ),
    );
  }

  List<Widget> _cards() {
    final cards = ref.watch(myCardsProvider(_category));
    return cards.when(
      loading: () => const [
        Padding(padding: EdgeInsets.all(32), child: LoadingView()),
      ],
      error: (e, _) => [
        ErrorView(
          error: e,
          onRetry: () => ref.invalidate(myCardsProvider(_category)),
        ),
      ],
      data: (page) => page.cards.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _category.isEmpty
                      ? "You haven't written a card yet. Share an idea in "
                            'your own words: people who follow you see it in '
                            'their timeline.'
                      : 'No cards here yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            ]
          : [
              for (final c in page.cards)
                ReadingWidth(child: MyCardTile(card: c)),
            ],
    );
  }
}

/// One of my cards in the list: title, topic and category, its media and
/// who can see it.
class MyCardTile extends ConsumerWidget {
  const MyCardTile({super.key, required this.card});
  final IdeaCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(topicNamesProvider);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return ListTile(
      key: ValueKey('my-card-${card.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(card.title, style: theme.textTheme.titleMedium),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            VisibilityBadge(visibility: card.visibility),
            Text(
              [
                names[card.topic] ?? card.topic,
                if (card.category != null) card.category!.name,
              ].join(' · '),
            ),
            if (card.image != null)
              Icon(Icons.image_outlined, size: 16, color: muted),
            if (card.audio != null)
              Icon(Icons.headphones_outlined, size: 16, color: muted),
            if (card.video != null)
              Icon(Icons.movie_outlined, size: 16, color: muted),
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(
        '/me/cards/${Uri.encodeComponent(card.id)}',
        extra: card,
      ),
    );
  }
}

/// Who a card is shown to: Everyone, Followers, Subscribers, Only me, or
/// Hidden (taken down after reports).
class VisibilityBadge extends StatelessWidget {
  const VisibilityBadge({super.key, required this.visibility});
  final String? visibility;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hidden = visibility == 'hidden';
    final color = hidden
        ? theme.colorScheme.error
        : Candlelight.of(context).amberText;
    return Container(
      key: const ValueKey('visibility-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: color)),
      ),
      child: Text(
        audienceLabel(visibility),
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

/// Creates a category, returning it (or null when cancelled or refused).
Future<CardCategory?> createCategory(
  BuildContext context,
  WidgetRef ref,
) async {
  final name = await askStashName(context, title: 'New category');
  if (name == null || !context.mounted) return null;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final c = await ref.read(repositoryProvider).createCategory(name);
    ref.invalidate(myCategoriesProvider);
    return c;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    return null;
  }
}

/// Lists my categories to add, rename and delete them.
Future<void> showCategoriesSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CategoriesSheet(),
    );

class _CategoriesSheet extends ConsumerWidget {
  const _CategoriesSheet();

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    CardCategory c,
  ) async {
    final name = await askStashName(
      context,
      initial: c.name,
      title: 'Rename category',
    );
    if (name == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(repositoryProvider).renameCategory(c.id, name);
      ref.invalidate(myCategoriesProvider);
      ref.invalidate(myCardsProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    CardCategory c,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete “${c.name}”?'),
        content: const Text('Its cards stay, without a category.'),
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
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(repositoryProvider).deleteCategory(c.id);
      ref.invalidate(myCategoriesProvider);
      ref.invalidate(myCardsProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cats = ref.watch(myCategoriesProvider);
    return SafeArea(
      child: ReadingWidth(
        maxWidth: 520,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Categories', style: theme.textTheme.titleLarge),
              ),
              Flexible(
                child: cats.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(24),
                    child: LoadingView(),
                  ),
                  error: (e, _) => ErrorView(
                    error: e,
                    onRetry: () => ref.invalidate(myCategoriesProvider),
                  ),
                  data: (list) => ListView(
                    shrinkWrap: true,
                    children: [
                      if (list.isEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Text(
                            'Group your cards your own way, like “Morning '
                            'habits” or “Notes on money”.',
                          ),
                        ),
                      for (final c in list)
                        ListTile(
                          key: ValueKey('category-${c.id}'),
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(c.name),
                          subtitle: c.cardCount == null
                              ? null
                              : Text(
                                  '${c.cardCount} '
                                  '${c.cardCount == 1 ? 'card' : 'cards'}',
                                ),
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Category options',
                            onSelected: (v) => v == 'rename'
                                ? _rename(context, ref, c)
                                : _delete(context, ref, c),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'rename',
                                child: Text('Rename'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: OutlinedButton.icon(
                  key: const ValueKey('new-category'),
                  onPressed: () => createCategory(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('New category'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
