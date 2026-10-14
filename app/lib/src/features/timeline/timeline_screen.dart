import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../layout/adaptive.dart';
import '../../theme.dart';
import '../../tv/tv_home.dart';
import '../../tv/tv_mode.dart';
import '../../widgets/common.dart';
import '../card/video_autoplay.dart';
import '../daily/daily_screen.dart';
import '../listen/listen_controller.dart';
import '../notifications/notifications_controller.dart';
import '../notifications/notifications_screen.dart';
import '../post/post_store.dart';
import '../post/post_view.dart';
import '../streak/streak_card.dart';
import '../summary/summary_widgets.dart';
import 'seen_tracker.dart';
import 'timeline_controller.dart';

/// Below this width (Material's compact window size) the timeline is the
/// full-screen swipe feed. At or above it the layout follows the window
/// size class:
/// - medium (600-839, a tablet in portrait): two columns of post cards
///   when each gets at least [kGridMinColumnWidth], else one column;
/// - expanded (840-1199, a tablet in landscape): one reading column with a
///   side panel (today's idea, streak, trending);
/// - large (1200+): two columns of post cards and the side panel.
const kSwipeFeedBreakpoint = WindowSize.mediumMin;

/// The narrowest a post card gets in the two-column grid.
const kGridMinColumnWidth = 320.0;

/// Width of the timeline's side panel on expanded and large windows.
const kTimelineSidePanelWidth = 340.0;

/// Start fetching the next page when this many posts or fewer are left.
const kPreloadRemaining = 3;

/// A video in the column feed plays once this much of it is on screen.
const kVideoVisibleFraction = 0.6;

/// Home: the timeline of posts, newest unseen first, endless, with pull to
/// refresh. On phones one post fills the screen and a swipe moves exactly
/// one post; on wide screens posts scroll in a column. Works signed out.
class TimelineScreen extends ConsumerStatefulWidget {
  const TimelineScreen({super.key, this.dwell = const Duration(seconds: 1)});

  /// How long a post must be at least half visible to count as seen.
  final Duration dwell;

  @override
  ConsumerState<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends ConsumerState<TimelineScreen> {
  final _scroll = ScrollController();
  final _listKey = GlobalKey();
  final _probes = <String, BuildContext>{};
  final _videos = VideoAutoplay();
  late final SeenTracker _tracker;
  late final AppLifecycleListener _lifecycle;
  bool _measureScheduled = false;

  /// The post on screen, where Listen mode starts: the swipe feed's page,
  /// or the most visible post in the column feed.
  int _swipePage = 0;
  String? _onScreen;

  @override
  void initState() {
    super.initState();
    final RebornRepository repo = ref.read(repositoryProvider);
    _tracker = SeenTracker(
      onFlush: repo.markSeen,
      onRead: repo.recordView,
      dwell: widget.dwell,
    );
    _videos.onAttach = _scheduleMeasure;
    _lifecycle = AppLifecycleListener(
      onStateChange: (s) =>
          _videos.setForeground(s == AppLifecycleState.resumed),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _tracker.dispose();
    _videos.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _register(String id, BuildContext context) {
    _probes[id] = context;
    _scheduleMeasure();
  }

  void _unregister(String id) {
    _probes.remove(id);
    _tracker.update(id, 0);
  }

  void _scheduleMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      _measure();
    });
  }

  /// Column feed only: reports each post's visible fraction (a post taller
  /// than the viewport counts as fully visible when it fills the viewport),
  /// and plays the most visible video that is at least 60% on screen.
  void _measure() {
    if (!mounted) return;
    final vp = _listKey.currentContext?.findRenderObject();
    if (vp is! RenderBox || !vp.attached || !vp.hasSize) return;
    final vpRect = vp.localToGlobal(Offset.zero) & vp.size;
    Rect? visibleOf(BuildContext context) {
      final box = context.findRenderObject();
      if (box is! RenderBox ||
          !box.attached ||
          !box.hasSize ||
          box.size.height <= 0) {
        return null;
      }
      final r = box.localToGlobal(Offset.zero) & box.size;
      final visible = r.intersect(vpRect);
      if (visible.width <= 0 || visible.height <= 0) return null;
      return r;
    }

    // The most visible video wins; on a tie, the one nearer the top.
    String? best;
    var bestFraction = 0.0;
    var bestTop = double.infinity;
    for (final e in _videos.players.entries) {
      final r = visibleOf(e.value);
      if (r == null) continue;
      final f = r.intersect(vpRect).height / r.height;
      if (f < kVideoVisibleFraction) continue;
      if (f > bestFraction + 0.001 ||
          ((f - bestFraction).abs() <= 0.001 && r.top < bestTop)) {
        best = e.key;
        bestFraction = f;
        bestTop = r.top;
      }
    }
    _videos.setActive(best);

    final signedIn = ref.read(sessionProvider).signedIn;
    String? onScreen;
    var onScreenFraction = 0.0;
    var onScreenTop = double.infinity;
    for (final e in _probes.entries) {
      var fraction = 0.0;
      final r = visibleOf(e.value);
      if (r != null) {
        fraction =
            r.intersect(vpRect).height / math.min(r.height, vpRect.height);
        if (fraction > onScreenFraction + 0.001 ||
            ((fraction - onScreenFraction).abs() <= 0.001 &&
                r.top < onScreenTop)) {
          onScreen = e.key;
          onScreenFraction = fraction;
          onScreenTop = r.top;
        }
      }
      if (signedIn) _tracker.update(e.key, fraction);
    }
    _onScreen = onScreen;
  }

  /// Starts Listen mode from the post on screen (or the top of the feed),
  /// with the feed's topic filter, and opens the player.
  void _listen() {
    final state = ref.read(timelineProvider).value;
    if (state == null || state.posts.isEmpty) return;
    var index = WindowSize.of(context).isCompact
        ? _swipePage
        : state.posts.indexWhere((p) => p.id == _onScreen);
    if (index < 0 || index >= state.posts.length) index = 0;
    // Listen mode plays the card posts; summary posts have their own Listen.
    final cards = state.posts.where((p) => !p.isSummary).toList();
    if (cards.isEmpty) return;
    index = state.posts.take(index).where((p) => !p.isSummary).length;
    ref
        .read(listenProvider.notifier)
        .startTimeline(
          posts: cards,
          index: index.clamp(0, cards.length - 1),
          cursor: state.nextCursor,
          topics: ref.read(timelineProvider.notifier).topics,
        );
    context.push('/listen');
  }

  Future<void> _refresh() {
    _tracker.flush();
    ref.read(postStoreProvider.notifier).forget();
    if (ref.read(sessionProvider).signedIn) {
      ref
        ..invalidate(streakProvider)
        ..invalidate(notificationsProvider);
    }
    return ref.refresh(timelineProvider.future);
  }

  void _loadMore() => ref.read(timelineProvider.notifier).loadMore();

  /// Fetches the next page when the reader is [kPreloadRemaining] posts or
  /// fewer from the end. A failed page waits for "Try again".
  void _preload(TimelineState state, int index) {
    if (!state.hasMore || state.loadingMore || state.loadMoreError != null) {
      return;
    }
    if (state.posts.length - 1 - index > kPreloadRemaining) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadMore();
    });
  }

  /// Skips the posts the server already counts as seen.
  void _skipSeen(TimelineState state) => _tracker.skip([
    for (final p in state.posts)
      if (p.isSummary || (p.viewer?.seen ?? false)) p.id,
  ]);

  @override
  Widget build(BuildContext context) {
    if (ref.watch(isTvProvider)) return const TvHome();
    final timeline = ref.watch(timelineProvider);
    final signedIn = ref.watch(sessionProvider.select((s) => s.signedIn));
    final size = WindowSize.of(context);
    final swipe = size.isCompact;
    ref.listen(timelineFilterProvider, (_, _) {
      _swipePage = 0;
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
    return Scaffold(
      appBar: AppBar(
        title: const Wordmark(),
        actions: [
          IconButton(
            key: const ValueKey('listen-feed'),
            tooltip: 'Listen',
            icon: const Icon(Icons.headphones_outlined),
            onPressed: _listen,
          ),
          IconButton(
            tooltip: 'Swipe through ideas',
            icon: const Icon(Icons.swipe_vertical_outlined),
            onPressed: () => context.push('/feed'),
          ),
          const NotificationBell(),
          const ProfileMenuButton(),
          const SizedBox(width: 8),
        ],
      ),
      body: VideoAutoplayScope(
        controller: _videos,
        child: Column(
          children: [
            const _TopicChips(),
            Expanded(
              child: timeline.when(
                loading: () => const LoadingView(),
                error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(timelineProvider),
                ),
                data: (state) {
                  _skipSeen(state);
                  return swipe
                      ? _SwipeFeed(
                          state: state,
                          signedIn: signedIn,
                          tracker: _tracker,
                          videos: _videos,
                          onRefresh: _refresh,
                          onPreload: _preload,
                          onLoadMore: _loadMore,
                          onPage: (i) => _swipePage = i,
                        )
                      : _wide(state, signedIn, size);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tablet and desktop layouts; see [kSwipeFeedBreakpoint].
  Widget _wide(TimelineState state, bool signedIn, WindowSize size) {
    final side = size.isTwoPane;
    return LayoutBuilder(
      builder: (context, c) {
        final listWidth = c.maxWidth - (side ? kTimelineSidePanelWidth : 0);
        // Expanded windows read best as one column beside the panel; the
        // others get two columns when each card still has room.
        final columns = size == WindowSize.expanded
            ? 1
            : ((listWidth - 16) / kGridMinColumnWidth).floor().clamp(1, 2);
        final list = _list(state, signedIn, columns: columns, header: !side);
        if (!side) return list;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: list),
            SizedBox(
              width: kTimelineSidePanelWidth,
              child: _SidePanel(signedIn: signedIn),
            ),
          ],
        );
      },
    );
  }

  /// The posts in one reading column, or in rows of [columns] cards. With
  /// [header], today's idea and the streak (or sign-up prompt) come first.
  Widget _list(
    TimelineState state,
    bool signedIn, {
    int columns = 1,
    bool header = true,
  }) {
    _scheduleMeasure();
    final maxWidth = columns == 1 ? kReadingWidth : 1180.0;
    Widget width(Widget child) =>
        ReadingWidth(maxWidth: maxWidth, child: child);
    final entries = <Widget Function()>[
      if (header) ...[
        () => width(const DailyBanner()),
        if (signedIn) () => width(const StreakCard()),
        if (!signedIn) () => width(const JoinPrompt()),
      ],
    ];
    Widget cell(int i) {
      final post = state.posts[i];
      // Built a few posts before the end: fetch the next page.
      _preload(state, i);
      if (post.summary != null) {
        return Padding(
          key: ValueKey('timeline-${post.id}'),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: SummaryPostCard(summary: post.summary!),
        );
      }
      return _SeenProbe(
        key: ValueKey('timeline-${post.id}'),
        id: post.id,
        register: _register,
        unregister: _unregister,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Card(child: PostView(post: post, showReason: true)),
        ),
      );
    }

    final caughtUp = state.caughtUp ?? -1;
    var i = 0;
    while (i < state.posts.length) {
      if (i == caughtUp) {
        entries.add(() => width(const CaughtUp()));
      }
      // A row never spans the caught-up line.
      final end = math.min(
        i + columns,
        (caughtUp > i && caughtUp < state.posts.length)
            ? caughtUp
            : state.posts.length,
      );
      final row = [for (var j = i; j < end; j++) j];
      entries.add(() {
        if (columns == 1) return width(cell(row.single));
        return width(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < columns; c++)
                  Expanded(
                    child: c < row.length ? cell(row[c]) : const SizedBox(),
                  ),
              ],
            ),
          ),
        );
      });
      i = end;
    }
    entries.add(
      () => ReadingWidth(
        child: _FeedEnd(
          state: state,
          onRetry: _loadMore,
          onRefresh: _refresh,
          onLoad: () => _preload(state, state.posts.length - 1),
        ),
      ),
    );
    return RefreshIndicator(
      onRefresh: _refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          _scheduleMeasure();
          return false;
        },
        child: KeyedSubtree(
          key: ValueKey(columns == 1 ? 'timeline-column' : 'timeline-grid'),
          child: ListView.builder(
            key: _listKey,
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: entries.length,
            itemBuilder: (_, i) => entries[i](),
          ),
        ),
      ),
    );
  }
}

/// Beside the timeline on expanded and large windows: today's idea, the
/// streak (or the sign-up prompt) and what's trending this week.
class _SidePanel extends ConsumerWidget {
  const _SidePanel({required this.signedIn});
  final bool signedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final trending = ref.watch(discoverProvider).value?.trending ?? const [];
    return ListView(
      key: const ValueKey('timeline-side-panel'),
      padding: const EdgeInsets.fromLTRB(0, 4, 8, 24),
      children: [
        const DailyBanner(),
        if (signedIn) const StreakCard() else const JoinPrompt(),
        if (trending.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
            child: Text(
              'Trending this week',
              style: theme.textTheme.titleMedium,
            ),
          ),
          for (final p in trending.take(5)) CardTile(card: p.card),
        ],
      ],
    );
  }
}

/// The phone timeline: one post per page, swiped vertically with snapping.
/// Each page fits the screen (a long post is cut short, with "Read more"
/// for the full card), so a swipe always moves one post. The current page counts as on screen for the seen and read
/// rules, and its video (if any) is the one that plays.
class _SwipeFeed extends StatefulWidget {
  const _SwipeFeed({
    required this.state,
    required this.signedIn,
    required this.tracker,
    required this.videos,
    required this.onRefresh,
    required this.onPreload,
    required this.onLoadMore,
    this.onPage,
  });

  final TimelineState state;
  final bool signedIn;
  final SeenTracker tracker;
  final VideoAutoplay videos;
  final Future<void> Function() onRefresh;
  final void Function(TimelineState state, int index) onPreload;
  final VoidCallback onLoadMore;

  /// The page now on screen.
  final ValueChanged<int>? onPage;

  @override
  State<_SwipeFeed> createState() => _SwipeFeedState();
}

class _SwipeFeedState extends State<_SwipeFeed> {
  final _pages = PageController();
  final _focus = FocusNode(debugLabel: 'swipe feed');
  int _page = 0;
  bool _turning = false;

  List<Post> get _posts => widget.state.posts;

  @override
  void initState() {
    super.initState();
    _scheduleSync();
    // Arrow keys work straight away, even after tapping a topic chip.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final focused = FocusManager.instance.primaryFocus?.context?.widget;
      if (mounted && focused is! EditableText) _focus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(_SwipeFeed old) {
    super.didUpdateWidget(old);
    // A new page of posts can land under the current page (the loading
    // page becomes the next post), and a refresh replaces them all.
    if (old.state != widget.state || old.signedIn != widget.signedIn) {
      _scheduleSync();
    }
  }

  @override
  void dispose() {
    widget.tracker.focus(null);
    widget.videos.setActive(null);
    _pages.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scheduleSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync();
    });
  }

  /// Points the seen tracker and the video player at the current page, and
  /// preloads when near the end.
  void _sync() {
    final post = _page < _posts.length ? _posts[_page] : null;
    widget.tracker.focus(
      widget.signedIn && !(post?.isSummary ?? false) ? post?.id : null,
    );
    widget.videos.setActive(
      post?.card.explainer != null ? post!.card.id : null,
    );
    widget.onPreload(widget.state, _page);
  }

  void _onPage(int index) {
    _page = index;
    widget.onPage?.call(index);
    _sync();
    setState(() {}); // page position semantics
  }

  /// Moves exactly one page; used by the keys.
  Future<void> _turn(int delta) async {
    if (_turning || !_pages.hasClients) return;
    final target = _page + delta;
    if (target < 0 || target > _posts.length) return;
    _turning = true;
    await _pages.animateToPage(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
    _turning = false;
  }

  Map<ShortcutActivator, VoidCallback> get _keys => {
    const SingleActivator(LogicalKeyboardKey.arrowDown): () => _turn(1),
    const SingleActivator(LogicalKeyboardKey.pageDown): () => _turn(1),
    const SingleActivator(LogicalKeyboardKey.keyJ): () => _turn(1),
    const SingleActivator(LogicalKeyboardKey.space): () => _turn(1),
    const SingleActivator(LogicalKeyboardKey.arrowUp): () => _turn(-1),
    const SingleActivator(LogicalKeyboardKey.pageUp): () => _turn(-1),
    const SingleActivator(LogicalKeyboardKey.keyK): () => _turn(-1),
  };

  List<Widget> _header(int index) {
    final caughtUp = widget.state.caughtUp;
    return [
      if (index == 0) ...[
        const DailyBanner(),
        if (widget.signedIn) const StreakCard() else const JoinPrompt(),
      ],
      if (index == caughtUp) const CaughtUp(),
    ];
  }

  Widget _buildPage(BuildContext context, int index) {
    final state = widget.state;
    final total = _posts.length;
    if (index >= total) {
      return Semantics(
        container: true,
        label: 'End of the feed',
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              ..._header(index),
              _FeedEnd(
                state: state,
                onRetry: widget.onLoadMore,
                onRefresh: widget.onRefresh,
                onLoad: () => widget.onPreload(state, total - 1),
              ),
            ],
          ),
        ),
      );
    }
    final post = _posts[index];
    final more = state.hasMore ? ', more loading as you go' : '';
    return Semantics(
      key: ValueKey('page-${post.id}'),
      container: true,
      label: 'Post ${index + 1} of $total$more',
      child: post.summary != null
          ? SwipeSummaryPage(
              summary: post.summary!,
              header: _header(index),
              footer: index == 0 ? const _SwipeHint() : null,
            )
          : SwipePostPage(
              post: post,
              header: _header(index),
              footer: index == 0 ? const _SwipeHint() : null,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _posts.length + 1; // the end page
    return CallbackShortcuts(
      bindings: _keys,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: RefreshIndicator(
          onRefresh: () async {
            await widget.onRefresh();
            if (mounted && _pages.hasClients) _pages.jumpToPage(0);
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification && !_focus.hasFocus) {
                _focus.requestFocus();
              }
              return false;
            },
            child: PageView.builder(
              key: const ValueKey('swipe-feed'),
              controller: _pages,
              scrollDirection: Axis.vertical,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: count,
              onPageChanged: _onPage,
              findChildIndexCallback: (key) {
                if (key is! ValueKey<String>) return null;
                final i = _posts.indexWhere((p) => 'page-${p.id}' == key.value);
                return i < 0 ? null : i;
              },
              itemBuilder: _buildPage,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Swipe up for the next idea", under the first post.
class _SwipeHint extends StatelessWidget {
  const _SwipeHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.keyboard_arrow_up, size: 18, color: color),
            Text(
              'Swipe up for the next idea',
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// The end of what's loaded: a spinner while the next page loads (never a
/// stop), "Try again" inline when it failed, or the true end of the feed.
class _FeedEnd extends StatelessWidget {
  const _FeedEnd({
    required this.state,
    required this.onRetry,
    required this.onRefresh,
    required this.onLoad,
  });

  final TimelineState state;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;

  /// Asks for the next page when this comes into view.
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final error = state.loadMoreError;
    if (error != null) {
      return Padding(
        key: const ValueKey('load-more-error'),
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          children: [
            Text(
              "Couldn't load more ideas.",
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              errorMessage(error),
              textAlign: TextAlign.center,
              style: muted,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('load-more-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    if (state.hasMore || state.loadingMore) {
      onLoad();
      return const Padding(padding: EdgeInsets.all(24), child: LoadingView());
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        children: [
          Text(
            state.posts.isEmpty
                ? 'Nothing here yet. Try another topic, or follow books and authors.'
                : "That's everything for now.",
            textAlign: TextAlign.center,
            style: muted,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Check for new ideas'),
          ),
        ],
      ),
    );
  }
}

/// Registers its child's render box so the timeline can measure visibility.
class _SeenProbe extends StatefulWidget {
  const _SeenProbe({
    super.key,
    required this.id,
    required this.register,
    required this.unregister,
    required this.child,
  });
  final String id;
  final void Function(String id, BuildContext context) register;
  final void Function(String id) unregister;
  final Widget child;

  @override
  State<_SeenProbe> createState() => _SeenProbeState();
}

class _SeenProbeState extends State<_SeenProbe> {
  @override
  void initState() {
    super.initState();
    widget.register(widget.id, context);
  }

  @override
  void dispose() {
    widget.unregister(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Marks where unseen posts end and already-seen ones begin.
class CaughtUp extends StatelessWidget {
  const CaughtUp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      key: const ValueKey('caught-up'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.check_circle_outline, color: scheme.primary),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 6),
          Text("You're all caught up", style: theme.textTheme.titleMedium),
          Text(
            "Ideas you've already seen are below.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown to signed-out readers at the top of the timeline.
class JoinPrompt extends StatelessWidget {
  const JoinPrompt({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        color: scheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Make Reborn yours',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Create a free account to react, save favourites, comment, '
                "follow books and authors, and pick up where you left off.",
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: () => context.push('/register'),
                    child: const Text('Sign up'),
                  ),
                  TextButton(
                    onPressed: () => context.push('/signin'),
                    child: const Text('Sign in'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicChips extends ConsumerWidget {
  const _TopicChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(topicsProvider).value ?? kDefaultTopics;
    // The reader's own topics first, in catalogue order, then the rest.
    final mine = ref.watch(topicPrefsProvider).toSet();
    final topics = [
      ...all.where((t) => mine.contains(t.slug)),
      ...all.where((t) => !mine.contains(t.slug)),
    ];
    final selected = ref.watch(timelineFilterProvider);
    final notifier = ref.read(timelineFilterProvider.notifier);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: const Text('For you'),
              selected: selected == null,
              onSelected: (_) => notifier.select(null),
            ),
          ),
          for (final t in topics)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(t.name),
                selected: selected == t.slug,
                onSelected: (on) => notifier.select(on ? t.slug : null),
              ),
            ),
        ],
      ),
    );
  }
}
