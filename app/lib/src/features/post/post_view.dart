import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../card/card_view.dart';
import '../card/explainer_player.dart';
import '../card/illustrated_video_player.dart';
import '../gifts/gift_sheet.dart';
import '../listen/listen_controller.dart';
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
        IdeaCardView(
          card: p.card,
          label: label,
          showShare: false,
          byline: AuthorByline.inline(card: p.card),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
        ),
        PostActionBar(post: p),
      ],
    );
  }
}

/// A post filling one page of the swipe feed, with no scrolling inside it:
/// optional [header] widgets, then a preview of the card cut to fit the
/// page (topic, title, source and as much of the body as fits) with a
/// "Read more" button that opens the full card screen. The action bar stays
/// pinned at the bottom so reacting, favouriting, comments and share are
/// always in reach, and every drag goes to the feed.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...header,
                Expanded(
                  child: Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: _FitAtLeast(
                      minHeight: 180,
                      child: PostPreview(post: p),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        PostActionBar(post: p, listen: true),
        ?footer,
      ],
    );
  }
}

/// Gives [child] the height it's offered, but never less than [minHeight]
/// (clipped at the bottom then), so a crowded first page can't overflow.
class _FitAtLeast extends StatelessWidget {
  const _FitAtLeast({required this.minHeight, required this.child});
  final double minHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      if (c.maxHeight >= minHeight) return child;
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: minHeight,
          maxHeight: minHeight,
          child: child,
        ),
      );
    },
  );
}

/// The swipe-feed preview of a post: why it's here, topic, title (or the
/// video sized to fit, title under it), source, the body cut to the lines
/// that fit, any health note, and "Read more" for the full card.
class PostPreview extends ConsumerWidget {
  const PostPreview({super.key, required this.post});
  final Post post;

  void _open(BuildContext context) => context.push(
    '/cards/${Uri.encodeComponent(post.card.id)}',
    extra: post.card,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final card = post.card;
    final reason = post.reason;
    final topicName = ref.watch(topicNamesProvider)[card.topic] ?? card.topic;
    final body = card.body
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .join('\n\n');
    final disclaimer =
        card.disclaimer ?? (card.health ? kHealthDisclaimerFallback : null);
    final explainer = card.explainer;
    final illustrated = explainer == null ? card.video : null;
    final video = explainer ?? illustrated;

    final title = Text(
      card.title,
      key: const ValueKey('preview-title'),
      maxLines: video == null ? 3 : 2,
      overflow: TextOverflow.ellipsis,
      style: video == null
          ? theme.textTheme.headlineSmall
          : theme.textTheme.titleLarge,
    );
    final readMore = Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.tonalIcon(
        key: const ValueKey('read-more'),
        onPressed: () => _open(context),
        icon: const Icon(Icons.arrow_forward, size: 18),
        label: Text('Read more', semanticsLabel: 'Read more: ${card.title}'),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (reason != null) PostReasonLine(reason: reason),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: CategoryTag(topicName),
          ),
        ),
        if (video != null) ...[
          Flexible(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: LayoutBuilder(
                builder: (context, c) => explainer != null
                    ? ExplainerPlayer(
                        explainer: explainer,
                        title: card.title,
                        autoplayId: card.id,
                        maxHeight: c.maxHeight,
                      )
                    : Center(
                        child: IllustratedVideoPlayer(
                          video: illustrated!,
                          title: card.title,
                          maxHeight: c.maxHeight,
                        ),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: title,
          ),
          AuthorByline(card: card),
        ] else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: title,
          ),
          AuthorByline(card: card),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: _FittedBody(text: body, style: theme.textTheme.bodyLarge),
            ),
          ),
        ],
        if (disclaimer != null)
          Padding(
            key: const ValueKey('preview-disclaimer'),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.health_and_safety_outlined,
                  size: 16,
                  color: Candlelight.of(context).amberText,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    disclaimer,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        // The full card always has more than the preview (the "Apply it"
        // step, any quote, the full credit), so a text post always offers
        // it; a video post when there's text to read.
        if (video == null || body.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: readMore,
          )
        else
          const SizedBox(height: 12),
      ],
    );
  }
}

/// The body cut to the whole lines that fit the height it's given, ending
/// in an ellipsis when it's cut.
class _FittedBody extends StatelessWidget {
  const _FittedBody({required this.text, this.style});
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      if (text.isEmpty) return const SizedBox.shrink();
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: c.maxWidth);
      var lines = 0;
      var used = 0.0;
      for (final m in painter.computeLineMetrics()) {
        if (used + m.height > c.maxHeight) break;
        used += m.height;
        lines++;
      }
      painter.dispose();
      if (lines == 0) return const SizedBox.shrink();
      return Text(
        text,
        key: const ValueKey('preview-body'),
        maxLines: lines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    },
  );
}

/// The small "why you're seeing this" line above a timeline post.
class PostReasonLine extends StatelessWidget {
  const PostReasonLine({super.key, required this.reason});
  final PostReason reason;

  IconData get _icon => switch (reason.kind) {
    'source' => Icons.menu_book_outlined,
    'author' => Icons.person_outline,
    'writer' => Icons.edit_note,
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
/// each author name opens the author screen. A card a member wrote reads
/// "by `name`" instead, opening their profile.
class AuthorByline extends StatelessWidget {
  const AuthorByline({super.key, required this.card}) : inline = false;

  /// Inside already padded content (the card page): the names line up with
  /// the text above, their tap targets reaching into the margin.
  const AuthorByline.inline({super.key, required this.card}) : inline = true;

  final IdeaCard card;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
    );
    final source = card.source;
    final writer = card.author;
    // The links' own padding spaces the dot.
    final dot = Text('·', style: theme.textTheme.bodySmall);
    final links = <Widget>[
      if (writer != null)
        _Link(
          key: const ValueKey('card-writer'),
          text: 'by ${writer.name}',
          style: style,
          onTap: writer.handle.isEmpty
              ? null
              : () => context.push(
                  '/users/${Uri.encodeComponent(writer.handle)}',
                ),
        ),
      if (writer == null) ...[
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
        for (final a in source.authors)
          _Link(
            key: ValueKey('author-$a'),
            text: a,
            style: style,
            onTap: () => context.push('/authors/${Uri.encodeComponent(a)}'),
          ),
      ],
    ];
    // Each separator stays at the end of the name before it, so a long
    // title never leaves a stray dot at the start of a line.
    final line = Wrap(
      key: const ValueKey('card-byline'),
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (i, link) in links.indexed)
          i == links.length - 1
              ? link
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: link),
                    dot,
                  ],
                ),
      ],
    );
    if (inline) {
      return Transform.translate(offset: const Offset(-6, 0), child: line);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: line,
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
  const PostActionBar({super.key, required this.post, this.listen = false});
  final Post post;

  /// Shows a Listen button for the post's card (the swipe feed, whose card
  /// preview has none of its own).
  final bool listen;

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
    final writer = post.card.author;
    final me = ref.watch(sessionProvider.select((s) => s.user?.id));
    // Writers can't gift their own cards; others can report a member's card.
    final mine = writer != null && me != null && writer.id == me;
    final reportable = writer != null && !mine && !post.isSummary;
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
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < (listen ? 390 : 330);
              void gift() {
                if (!ensureSignedIn(context, ref)) return;
                showGiftSheet(context, post);
              }

              return Row(
                children: [
                  _CountButton(
                    key: const ValueKey('post-favorite'),
                    label: 'Favourite',
                    toggled: post.favorited,
                    tooltip: post.favorited
                        ? 'Remove from favourites'
                        : 'Add to favourites',
                    icon: post.favorited
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: post.favorited
                        ? Candlelight.of(context).react
                        : null,
                    count: stats.favorites,
                    onPressed: () {
                      if (!ensureSignedIn(context, ref)) return;
                      _guard(context, () => store.toggleFavorite(post));
                    },
                  ),
                  _CountButton(
                    key: const ValueKey('post-comments'),
                    label: 'Comments',
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
                      label: 'Share',
                      tooltip: 'Share',
                      icon: Icons.ios_share,
                      count: stats.shares,
                      onPressed: () => sharePost(context, ref, post),
                    ),
                  ),
                  if (listen) _ListenPostButton(card: post.card),
                  const Spacer(),
                  // In a narrow column (the tablet grid) Gift is just its icon.
                  if (mine)
                    const SizedBox.shrink()
                  else if (narrow)
                    _CountButton(
                      key: const ValueKey('post-gift'),
                      label: 'Gift',
                      tooltip: 'Gift',
                      icon: Icons.volunteer_activism_outlined,
                      count: stats.gifts,
                      onPressed: gift,
                    )
                  else
                    TextButton.icon(
                      key: const ValueKey('post-gift'),
                      onPressed: gift,
                      icon: const Icon(
                        Icons.volunteer_activism_outlined,
                        size: 20,
                      ),
                      label: Text(
                        stats.gifts > 0
                            ? 'Gift · ${compactCount(stats.gifts)}'
                            : 'Gift',
                      ),
                    ),
                  if (reportable) _PostMenu(post: post),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// More actions on a member's card: Report.
class _PostMenu extends ConsumerWidget {
  const _PostMenu({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
    key: const ValueKey('post-menu'),
    tooltip: 'More',
    icon: Icon(
      Icons.more_vert,
      size: 20,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    onSelected: (_) {
      if (!ensureSignedIn(context, ref)) return;
      reportPost(context, ref, post);
    },
    itemBuilder: (_) => const [
      PopupMenuItem(
        value: 'report',
        child: Row(
          children: [
            Icon(Icons.flag_outlined, size: 20),
            SizedBox(width: 12),
            Text('Report'),
          ],
        ),
      ),
    ],
  );
}

/// Asks for an optional reason, then reports a member's card.
Future<void> reportPost(BuildContext context, WidgetRef ref, Post post) async {
  final controller = TextEditingController();
  final reason = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Report this card?'),
      content: TextField(
        controller: controller,
        maxLength: 300,
        maxLines: 3,
        minLines: 1,
        decoration: const InputDecoration(labelText: 'Reason (optional)'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('report-send'),
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: const Text('Report'),
        ),
      ],
    ),
  );
  if (reason == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(repositoryProvider).reportPost(post.id, reason: reason);
    messenger.showSnackBar(
      const SnackBar(content: Text("Thanks, we'll take a look")),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
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

/// Listen to one post's card: its recording, or the device voice. While
/// it's the card playing, pauses and resumes it.
class _ListenPostButton extends ConsumerWidget {
  const _ListenPostButton({required this.card});
  final IdeaCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (current, playing) = ref.watch(
      listenProvider.select((s) {
        final on = s.active && !s.finished && s.current?.card.id == card.id;
        return (on, on && s.playing);
      }),
    );
    final listen = ref.read(listenProvider.notifier);
    return IconButton(
      key: const ValueKey('post-listen'),
      tooltip: playing ? 'Pause this idea' : 'Listen to this idea',
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      onPressed: () {
        if (current) {
          listen.toggle();
        } else {
          listen.playCard(card);
        }
      },
      icon: Icon(
        playing ? Icons.pause_rounded : Icons.headphones_outlined,
        size: 22,
      ),
    );
  }
}

class _CountButton extends StatelessWidget {
  const _CountButton({
    super.key,
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.count,
    required this.onPressed,
    this.color,
    this.toggled,
  });

  /// What a screen reader announces before the count ("Favourite, 3"):
  /// otherwise it would hear only the number.
  final String label;
  final String tooltip;
  final IconData icon;
  final int count;
  final VoidCallback onPressed;
  final Color? color;

  /// For a toggle (favourite): whether it is on.
  final bool? toggled;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    toggled: toggled,
    label: '$label, $count',
    onTap: onPressed,
    excludeSemantics: true,
    child: Tooltip(
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
    ),
  );
}
