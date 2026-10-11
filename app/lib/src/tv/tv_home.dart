import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../data/providers.dart';
import '../data/repository.dart';
import '../features/shell/app_shell.dart';
import '../features/timeline/timeline_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'tv_mode.dart';

/// How many topic rows the TV home shows under the main rows.
const kTvTopicRows = 4;

class TvRow {
  const TvRow(this.id, this.title, this.posts);
  final String id;
  final String title;
  final List<Post> posts;
}

/// Home on a TV: rows of idea cards, like a streaming app. "For you" (the
/// timeline) first, then trending, new ideas and a row per topic. The
/// remote's arrows move along a row and between rows (each row remembers
/// where you were), Select opens the idea, Back returns here.
class TvHome extends ConsumerStatefulWidget {
  const TvHome({super.key});

  @override
  ConsumerState<TvHome> createState() => _TvHomeState();
}

class _TvHomeState extends ConsumerState<TvHome> {
  final _nodes = <String, FocusNode>{};
  final _lastCol = <String, int>{};
  List<TvRow> _rows = const [];
  bool _focusedOnce = false;

  @override
  void dispose() {
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  FocusNode _node(TvRow row, int col) {
    final node = _nodes.putIfAbsent(
      '${row.id}/${row.posts[col].id}',
      () => FocusNode(debugLabel: 'tv-card ${row.id}/$col'),
    );
    OwnFocusHighlight.mark(node);
    return node;
  }

  void _focus(int r, int? c) {
    final row = _rows[r];
    if (row.posts.isEmpty) return;
    final col = (c ?? _lastCol[row.id] ?? 0).clamp(0, row.posts.length - 1);
    _node(row, col).requestFocus();
  }

  /// Up or Down into row [r] from column [c] of another row: back to where
  /// that row was left, or (on a first visit) to the card nearest the same
  /// spot on screen, the usual leanback behaviour.
  void _focusVertical(int r, int fromRow, int c) {
    final row = _rows[r];
    if (row.posts.isEmpty) return;
    final last = _lastCol[row.id];
    if (last != null) return _focus(r, last);
    final from = _node(_rows[fromRow], c);
    if (from.context == null || from.rect.isEmpty) return _focus(r, c);
    final x = from.rect.center.dx;
    var best = c.clamp(0, row.posts.length - 1);
    var bestD = double.infinity;
    for (var i = 0; i < row.posts.length; i++) {
      final n = _node(row, i);
      if (n.context == null || n.rect.isEmpty) continue;
      final d = (n.rect.center.dx - x).abs();
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    _focus(r, best);
  }

  KeyEventResult _onKey(int r, int c, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      if (c + 1 < _rows[r].posts.length) _focus(r, c + 1);
      return KeyEventResult.handled; // the end of a row stops
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (c > 0) {
        _focus(r, c - 1);
      } else {
        // On to the menu.
        final nav = TvNav.maybeOf(context);
        if (nav == null) return KeyEventResult.ignored;
        nav.focusRail();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (r + 1 < _rows.length) _focusVertical(r + 1, r, c);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (r == 0) return KeyEventResult.ignored;
      _focusVertical(r - 1, r, c);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  List<TvRow> _buildRows() {
    final rows = <TvRow>[];
    void add(String id, String title, List<Post>? posts) {
      if (posts != null && posts.isNotEmpty) rows.add(TvRow(id, title, posts));
    }

    add('for-you', 'For you', ref.watch(timelineProvider).value?.posts);
    final discover = ref.watch(discoverProvider).value;
    add('trending', 'Trending this week', discover?.trending);
    add('new', 'New ideas', discover?.newPosts);
    final topics = ref.watch(topicsProvider).value ?? kDefaultTopics;
    for (final t in topics.take(kTvTopicRows)) {
      add('topic-${t.slug}', t.name, ref.watch(trendingProvider(t.slug)).value);
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeline = ref.watch(timelineProvider);
    _rows = _buildRows();
    Widget body;
    if (_rows.isEmpty) {
      body = timeline.hasError && !timeline.isLoading
          ? ErrorView(
              error: timeline.error!,
              onRetry: () => ref.invalidate(timelineProvider),
            )
          : timeline.isLoading
          ? const LoadingView()
          : const Center(child: Text('Nothing here yet.'));
    } else {
      if (!_focusedOnce) {
        _focusedOnce = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final focus = FocusManager.instance.primaryFocus;
          final inPage = focus?.context
              ?.findAncestorStateOfType<_TvHomeState>();
          if (mounted && inPage == null) _focus(0, 0);
        });
      }
      body = FocusTraversalGroup(
        // No scrollbar on a TV: focus moves the page.
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: ListView(
            key: const ValueKey('tv-rows'),
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (var r = 0; r < _rows.length; r++)
                _TvRowView(
                  key: ValueKey('tv-row-${_rows[r].id}'),
                  row: _rows[r],
                  nodeFor: (c) => _node(_rows[r], c),
                  onKey: (c, e) => _onKey(r, c, e),
                  onFocused: (c) => _lastCol[_rows[r].id] = c,
                  onOpen: (post) => context.push(
                    '/tv/cards/${Uri.encodeComponent(post.card.id)}',
                    extra: post,
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Wordmark(size: 30),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    'One-minute ideas from great books',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _TvRowView extends StatelessWidget {
  const _TvRowView({
    super.key,
    required this.row,
    required this.nodeFor,
    required this.onKey,
    required this.onFocused,
    required this.onOpen,
  });

  final TvRow row;
  final FocusNode Function(int col) nodeFor;
  final KeyEventResult Function(int col, KeyEvent e) onKey;
  final void Function(int col) onFocused;
  final void Function(Post post) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        // About three and a half cards across, so the row reads as one.
        final width = ((c.maxWidth - 48) / 3.4).clamp(200.0, 420.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Text(row.title, style: theme.textTheme.titleLarge),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(
                children: [
                  for (var i = 0; i < row.posts.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 18),
                      child: TvPostCard(
                        key: ValueKey('tv-card-${row.id}-${row.posts[i].id}'),
                        post: row.posts[i],
                        width: width,
                        focusNode: nodeFor(i),
                        onKey: (e) => onKey(i, e),
                        onFocused: () => onFocused(i),
                        onOpen: () => onOpen(row.posts[i]),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A poster-style card for a post: topic, title and book, over the video's
/// poster when it has one. Focused, it grows and gets an amber ring.
class TvPostCard extends ConsumerStatefulWidget {
  const TvPostCard({
    super.key,
    required this.post,
    required this.width,
    required this.focusNode,
    required this.onOpen,
    this.onKey,
    this.onFocused,
  });

  final Post post;
  final double width;
  final FocusNode focusNode;
  final VoidCallback onOpen;
  final KeyEventResult Function(KeyEvent e)? onKey;
  final VoidCallback? onFocused;

  @override
  ConsumerState<TvPostCard> createState() => _TvPostCardState();
}

class _TvPostCardState extends ConsumerState<TvPostCard> {
  bool _focused = false;

  void _onFocus(bool focused) {
    setState(() => _focused = focused);
    if (!focused) return;
    widget.onFocused?.call();
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = Candlelight.of(context);
    final card = widget.post.card;
    final topic = ref.watch(topicNamesProvider)[card.topic] ?? card.topic;
    final video = card.explainer;
    final height = widget.width * 0.72;
    final onVideo = video != null;
    final ink = onVideo ? const Color(0xFFF2E8D8) : theme.colorScheme.onSurface;
    final muted = onVideo ? const Color(0xFFD9CDBA) : c.muted;
    final source = [
      card.source.title,
      ...card.source.authors,
    ].where((s) => s.isNotEmpty).join(' · ');

    // A long topic shrinks a little to fit rather than being cut off
    // ("PERSONAL DEVELOPM…").
    final tag = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        topic.toUpperCase(),
        maxLines: 1,
        style: TextStyle(
          fontFamily: kBodyFont,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: onVideo ? CandlelightTokens.amber : c.amberText,
        ),
      ),
    );
    Widget title(int lines) => Text(
      card.title,
      maxLines: lines,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleMedium?.copyWith(color: ink, height: 1.2),
    );
    final sourceLine = Text(
      source,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(color: muted),
    );

    return Actions(
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onOpen();
            return null;
          },
        ),
      },
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: _onFocus,
        onKeyEvent: widget.onKey == null ? null : (_, e) => widget.onKey!(e),
        child: Semantics(
          button: true,
          label: '${card.title}. $topic. $source',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: widget.onOpen,
            child: AnimatedScale(
              scale: _focused ? 1.08 : 1,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: widget.width,
                height: height,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: onVideo
                      ? CandlelightTokens.videoBase
                      : theme.cardTheme.color ?? theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _focused ? CandlelightTokens.amber : c.line,
                    width: _focused ? 3 : 1,
                  ),
                  boxShadow: _focused
                      ? [
                          BoxShadow(
                            color: CandlelightTokens.amber.withValues(
                              alpha: 0.35,
                            ),
                            blurRadius: 24,
                          ),
                        ]
                      : null,
                ),
                child: video == null
                    ? Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            tag,
                            const Spacer(),
                            title(3),
                            const SizedBox(height: 6),
                            sourceLine,
                          ],
                        ),
                      )
                    // A video: its poster on top (it carries its own
                    // title art), the words on a dark band below.
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  resolveMediaUrl(video.posterUrl),
                                  fit: BoxFit.cover,
                                  alignment: const Alignment(0, -0.2),
                                  errorBuilder: (_, _, _) => const SizedBox(),
                                ),
                                // In the bottom-right corner, off the
                                // title printed on the poster.
                                const Positioned(
                                  right: 8,
                                  bottom: 8,
                                  child: DecoratedBox(
                                    key: ValueKey('tv-tile-play'),
                                    decoration: BoxDecoration(
                                      color: Color(0xB314110E),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.play_circle_fill,
                                      size: 36,
                                      color: CandlelightTokens.amber,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                tag,
                                const SizedBox(height: 2),
                                title(1),
                                const SizedBox(height: 2),
                                sourceLine,
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
