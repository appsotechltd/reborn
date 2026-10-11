import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../card/card_view.dart';
import '../gifts/gift_sheet.dart';
import 'post_store.dart';
import 'share.dart';

/// A post: the card (with its credit, licence link and any health disclaimer)
/// plus reactions, favourite, comments, share and gift. Used in the timeline
/// and on the card screen.
class PostView extends ConsumerWidget {
  const PostView({
    super.key,
    required this.post,
    this.showReason = false,
    this.label,
  });

  final Post post;

  /// Shows why the post is in the timeline ("From Meditations").
  final bool showReason;
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = watchPost(ref, post);
    final reason = p.reason;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showReason && reason != null) PostReasonLine(reason: reason),
        AuthorByline(card: p.card),
        IdeaCardView(
          card: p.card,
          label: label,
          showShare: false,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        ),
        PostActionBar(post: p),
      ],
    );
  }
}

/// A post filling one page of the swipe feed: optional [header] widgets and
/// the card scroll inside the page (a short post doesn't scroll at all, so
/// the swipe goes straight to the feed), and the action bar stays pinned at
/// the bottom so reacting, favouriting, comments and share are always in
/// reach.
class SwipePostPage extends ConsumerWidget {
  const SwipePostPage({
    super.key,
    required this.post,
    this.header = const [],
    this.footer,
  });

  final Post post;
  final List<Widget> header;

  /// Under the action bar, e.g. a swipe hint on the first page.
  final Widget? footer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = watchPost(ref, post);
    final reason = p.reason;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            // Not always-scrollable: a post that fits leaves drags to the
            // page view.
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...header,
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (reason != null) PostReasonLine(reason: reason),
                      AuthorByline(card: p.card),
                      IdeaCardView(
                        card: p.card,
                        showShare: false,
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        PostActionBar(post: p),
        ?footer,
      ],
    );
  }
}

/// The small "why you're seeing this" line above a timeline post.
class PostReasonLine extends StatelessWidget {
  const PostReasonLine({super.key, required this.reason});
  final PostReason reason;

  IconData get _icon => switch (reason.kind) {
    'source' => Icons.menu_book_outlined,
    'author' => Icons.person_outline,
    'favorite' => Icons.favorite_border,
    'topic' => Icons.tag,
    _ => Icons.auto_awesome_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      key: const ValueKey('post-reason'),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          Icon(_icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              reason.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Meditations · Marcus Aurelius": the book opens the source screen and
/// each author name opens the author screen.
class AuthorByline extends StatelessWidget {
  const AuthorByline({super.key, required this.card});
  final IdeaCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
    );
    final source = card.source;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (source.title.isNotEmpty)
            _Link(
              text: source.title,
              style: style,
              onTap: source.id.isEmpty
                  ? null
                  : () => context.push(
                      '/sources/${Uri.encodeComponent(source.id)}',
                    ),
            ),
          for (final a in source.authors) ...[
            Text(' · ', style: theme.textTheme.bodySmall),
            _Link(
              key: ValueKey('author-$a'),
              text: a,
              style: style,
              onTap: () => context.push('/authors/${Uri.encodeComponent(a)}'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({super.key, required this.text, this.style, this.onTap});
  final String text;
  final TextStyle? style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(6),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Text(text, style: style),
    ),
  );
}

/// Reactions with counts, then favourite, comments, share and gift.
class PostActionBar extends ConsumerWidget {
  const PostActionBar({super.key, required this.post});
  final Post post;

  Future<void> _guard(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(postStoreProvider.notifier);
    final stats = post.stats;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in Reaction.values)
                  _ReactionChip(
                    reaction: r,
                    count: stats.reactions[r.name] ?? 0,
                    selected: post.myReaction == r,
                    onTap: () {
                      if (!ensureSignedIn(context, ref)) return;
                      _guard(context, () => store.react(post, r));
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _CountButton(
                key: const ValueKey('post-favorite'),
                tooltip: post.favorited
                    ? 'Remove from favourites'
                    : 'Add to favourites',
                icon: post.favorited ? Icons.favorite : Icons.favorite_border,
                color: post.favorited ? Candlelight.of(context).react : null,
                count: stats.favorites,
                onPressed: () {
                  if (!ensureSignedIn(context, ref)) return;
                  _guard(context, () => store.toggleFavorite(post));
                },
              ),
              _CountButton(
                key: const ValueKey('post-comments'),
                tooltip: 'Comments',
                icon: Icons.mode_comment_outlined,
                count: stats.comments,
                onPressed: () => context.push(
                  '/posts/${Uri.encodeComponent(post.id)}/comments',
                  extra: post,
                ),
              ),
              Builder(
                builder: (context) => _CountButton(
                  key: const ValueKey('post-share'),
                  tooltip: 'Share',
                  icon: Icons.ios_share,
                  count: stats.shares,
                  onPressed: () => sharePost(context, ref, post),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                key: const ValueKey('post-gift'),
                onPressed: () {
                  if (!ensureSignedIn(context, ref)) return;
                  showGiftSheet(context, post);
                },
                icon: const Icon(Icons.volunteer_activism_outlined, size: 20),
                label: Text(
                  stats.gifts > 0
                      ? 'Gift · ${compactCount(stats.gifts)}'
                      : 'Gift',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.reaction,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final Reaction reaction;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final react = Candlelight.of(context).react;
    return Semantics(
      button: true,
      selected: selected,
      label: '${reaction.label}, $count',
      excludeSemantics: true,
      child: Tooltip(
        message: reaction.label,
        child: Material(
          key: ValueKey('reaction-${reaction.name}'),
          color: selected ? react.withValues(alpha: 0.12) : Colors.transparent,
          shape: StadiumBorder(
            side: BorderSide(color: selected ? react : scheme.outlineVariant),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(reaction.emoji, style: const TextStyle(fontSize: 15)),
                  const SizedBox(width: 4),
                  Text(
                    compactCount(count),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: selected ? react : scheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w700 : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CountButton extends StatelessWidget {
  const _CountButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.count,
    required this.onPressed,
    this.color,
  });
  final String tooltip;
  final IconData icon;
  final int count;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor:
            color ?? Theme.of(context).colorScheme.onSurfaceVariant,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      icon: Icon(icon, size: 20),
      label: Text(compactCount(count)),
    ),
  );
}
