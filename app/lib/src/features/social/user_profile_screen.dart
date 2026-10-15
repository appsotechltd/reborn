import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../blocks/block_actions.dart';
import '../post/share.dart';
import '../mycards/my_cards_screen.dart';
import '../premium/premium_screen.dart';
import '../writers/subscribe_box.dart';
import 'favorites_screen.dart';
import 'follow_button.dart';

/// A person's public profile by handle: the cards they write (with a
/// Subscribe box when they sell subscriptions), their favourites and their
/// public stashes (shown as collections).
class UserProfileScreen extends ConsumerStatefulWidget {
  const UserProfileScreen({super.key, required this.handle});
  final String handle;

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  int _tab = 0;

  /// The category filter on the Cards tab ('' for all).
  String _category = '';

  @override
  Widget build(BuildContext context) {
    final handle = widget.handle;
    final profile = ref.watch(profileProvider(handle));
    final p = profile.value;
    return Scaffold(
      appBar: AppBar(
        leading: exitLeading(context),
        title: Text('@$handle'),
        actions: [
          ShareLinkButton(
            key: const ValueKey('profile-share'),
            title: p == null || p.displayName.isEmpty
                ? '@$handle on Reborn'
                : '${p.displayName} on Reborn',
            path: '/u/${Uri.encodeComponent(handle)}',
          ),
          if (p != null && !p.isMe)
            BlockMenu(
              userId: p.id,
              name: p.displayName.isEmpty ? '@${p.handle}' : p.displayName,
            ),
        ],
      ),
      body: profile.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(profileProvider(handle)),
        ),
        data: (p) => ListView(
          children: [
            ReadingWidth(child: ProfileHeader(profile: p)),
            ReadingWidth(child: SubscribeBox(profile: p)),
            ReadingWidth(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      label: Text('Cards'),
                      icon: Icon(Icons.edit_note),
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Text('Favourites'),
                      icon: Icon(Icons.favorite_border),
                    ),
                    ButtonSegment(
                      value: 2,
                      label: Text('Collections'),
                      icon: Icon(Icons.bookmarks_outlined),
                    ),
                  ],
                  selected: {_tab},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setState(() => _tab = v.first),
                ),
              ),
            ),
            if (_tab == 0)
              ..._cards(p)
            else if (_tab == 1)
              ...favoriteTiles(
                context,
                ref,
                handle,
                empty: p.isMe
                    ? 'Tap the heart on an idea to add it here.'
                    : 'No favourites yet.',
              )
            else
              ..._stashes(p),
          ],
        ),
      ),
    );
  }

  List<Widget> _cards(Profile p) {
    final handle = widget.handle;
    // The writer's categories come with the unfiltered first page.
    final cats =
        ref
            .watch(userCardsProvider((handle: handle, category: '')))
            .value
            ?.categories ??
        const <CardCategory>[];
    final cards = ref.watch(
      userCardsProvider((handle: handle, category: _category)),
    );
    return [
      if (cats.isNotEmpty)
        ReadingWidth(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                for (final (id, name) in [
                  ('', 'All'),
                  for (final c in cats) (c.id, c.name),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey('user-category-${id.isEmpty ? 'all' : id}'),
                      label: Text(name),
                      selected: _category == id,
                      onSelected: (_) => setState(() => _category = id),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ...cards.when(
        loading: () => const [
          Padding(padding: EdgeInsets.all(32), child: LoadingView()),
        ],
        error: (e, _) => [
          ErrorView(
            error: e,
            onRetry: () => ref.invalidate(
              userCardsProvider((handle: handle, category: _category)),
            ),
          ),
        ],
        data: (page) => page.posts.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    p.isMe
                        ? 'Cards you write show here. Write one from My cards.'
                        : 'No cards yet.',
                    textAlign: TextAlign.center,
                  ),
                ),
                if (p.isMe)
                  Center(
                    child: OutlinedButton(
                      onPressed: () => context.push('/me/cards'),
                      child: const Text('My cards'),
                    ),
                  ),
              ]
            : [
                for (final post in page.posts)
                  ReadingWidth(child: _WriterCardTile(card: post.card)),
                const SizedBox(height: 24),
              ],
      ),
    ];
  }

  List<Widget> _stashes(Profile p) {
    final stashes = ref.watch(userStashesProvider(widget.handle));
    return stashes.when(
      loading: () => const [
        Padding(padding: EdgeInsets.all(32), child: LoadingView()),
      ],
      error: (e, _) => [
        ErrorView(
          error: e,
          onRetry: () => ref.invalidate(userStashesProvider(widget.handle)),
        ),
      ],
      data: (list) => list.isEmpty
          ? [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  p.isMe
                      ? 'No public collections. Make a collection public from its '
                            'page to show it here.'
                      : 'No public collections yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            ]
          : [
              for (final s in list)
                ReadingWidth(
                  child: ListTile(
                    key: ValueKey('public-stash-${s.id}'),
                    leading: const Icon(Icons.bookmarks_outlined),
                    title: Text(s.name),
                    subtitle: Text(
                      '${s.cardCount} ${s.cardCount == 1 ? 'idea' : 'ideas'}'
                      '${s.description.isEmpty ? '' : ' · ${s.description}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () =>
                        context.push('/s/${Uri.encodeComponent(s.id)}'),
                  ),
                ),
            ],
    );
  }
}

class ProfileHeader extends ConsumerWidget {
  const ProfileHeader({super.key, required this.profile});
  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final p = profile;
    final premium =
        p.isMe &&
        ref.watch(sessionProvider.select((s) => s.user?.premium ?? false));
    final name = p.displayName.isEmpty ? p.handle : p.displayName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PersonAvatar(name: name, radius: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.headlineSmall),
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('@${p.handle}', style: theme.textTheme.bodyMedium),
                        if (premium) const PremiumBadge(),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (p.bio.isNotEmpty) ...[const SizedBox(height: 12), Text(p.bio)],
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            children: [
              _Count(p.following, 'following'),
              _Count(
                p.favorites,
                p.favorites == 1 ? 'favourite' : 'favourites',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (p.isMe)
            OutlinedButton.icon(
              onPressed: () => context.push('/settings'),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit profile'),
            )
          else
            FollowButton(
              kind: FollowKind.user,
              target: p.id,
              initial: FollowState(
                followers: p.followers,
                isFollowing: p.isFollowing,
              ),
            ),
          if (p.isMe) ...[
            const SizedBox(height: 8),
            Text(
              '${compactCount(p.followers)} '
              '${p.followers == 1 ? 'follower' : 'followers'}',
            ),
          ],
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.n, this.label);
  final int n;
  final String label;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: compactCount(n),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        TextSpan(text: ' $label'),
      ],
    ),
  );
}

/// One of a writer's cards on their page: title, topic and category, and
/// who it's for when that isn't everyone.
class _WriterCardTile extends ConsumerWidget {
  const _WriterCardTile({required this.card});
  final IdeaCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(topicNamesProvider);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return ListTile(
      key: ValueKey('writer-card-${card.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(card.title, style: theme.textTheme.titleMedium),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (card.visibility != null && card.visibility != 'everyone')
              VisibilityBadge(visibility: card.visibility),
            Text(
              [
                names[card.topic] ?? card.topic,
                if (card.category != null) card.category!.name,
              ].join(' · '),
            ),
            if (card.video != null)
              Icon(Icons.movie_outlined, size: 16, color: muted)
            else if (card.audio != null)
              Icon(Icons.headphones_outlined, size: 16, color: muted),
          ],
        ),
      ),
      onTap: () =>
          context.push('/cards/${Uri.encodeComponent(card.id)}', extra: card),
    );
  }
}
