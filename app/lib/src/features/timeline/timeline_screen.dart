import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';
import '../daily/daily_screen.dart';
import '../post/post_store.dart';
import '../post/post_view.dart';
import 'seen_tracker.dart';
import 'timeline_controller.dart';

/// Home: the timeline of posts, newest unseen first, with infinite scroll
/// and pull to refresh. Works signed out.
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
  late final SeenTracker _tracker;
  bool _measureScheduled = false;

  @override
  void initState() {
    super.initState();
    final RebornRepository repo = ref.read(repositoryProvider);
    _tracker = SeenTracker(onFlush: repo.markSeen, dwell: widget.dwell);
  }

  @override
  void dispose() {
    _tracker.dispose();
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

  /// Reports each post's visible fraction. A post taller than the viewport
  /// counts as fully visible when it fills the viewport.
  void _measure() {
    if (!mounted || !ref.read(sessionProvider).signedIn) return;
    final vp = _listKey.currentContext?.findRenderObject();
    if (vp is! RenderBox || !vp.attached || !vp.hasSize) return;
    final vpRect = vp.localToGlobal(Offset.zero) & vp.size;
    for (final e in _probes.entries) {
      var fraction = 0.0;
      final box = e.value.findRenderObject();
      if (box is RenderBox &&
          box.attached &&
          box.hasSize &&
          box.size.height > 0) {
        final r = box.localToGlobal(Offset.zero) & box.size;
        final visible = r.intersect(vpRect);
        if (visible.width > 0 && visible.height > 0) {
          fraction = visible.height / math.min(r.height, vpRect.height);
        }
      }
      _tracker.update(e.key, fraction);
    }
  }

  Future<void> _refresh() {
    _tracker.flush();
    ref.read(postStoreProvider.notifier).forget();
    return ref.refresh(timelineProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final timeline = ref.watch(timelineProvider);
    final signedIn = ref.watch(sessionProvider.select((s) => s.signedIn));
    ref.listen(timelineFilterProvider, (_, _) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reborn'),
        actions: [
          IconButton(
            tooltip: 'Swipe through ideas',
            icon: const Icon(Icons.swipe_vertical_outlined),
            onPressed: () => context.push('/feed'),
          ),
          const ProfileMenuButton(),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          const _TopicChips(),
          Expanded(
            child: timeline.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.invalidate(timelineProvider),
              ),
              data: (state) => _list(state, signedIn),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(TimelineState state, bool signedIn) {
    // Posts the server already counts as seen aren't sent again.
    _tracker.skip([
      for (final p in state.posts)
        if (p.viewer?.seen ?? false) p.id,
    ]);
    _scheduleMeasure();
    final entries = <Widget Function()>[
      () => const ReadingWidth(child: DailyBanner()),
      if (!signedIn) () => const ReadingWidth(child: JoinPrompt()),
    ];
    final caughtUp = state.caughtUp;
    for (var i = 0; i < state.posts.length; i++) {
      if (i == caughtUp) {
        entries.add(() => const ReadingWidth(child: CaughtUp()));
      }
      final post = state.posts[i];
      entries.add(
        () => ReadingWidth(
          child: _SeenProbe(
            key: ValueKey('timeline-${post.id}'),
            id: post.id,
            register: _register,
            unregister: _unregister,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Card(child: PostView(post: post, showReason: true)),
            ),
          ),
        ),
      );
    }
    entries.add(() => _footer(state));
    return RefreshIndicator(
      onRefresh: _refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          _scheduleMeasure();
          return false;
        },
        child: ListView.builder(
          key: _listKey,
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: entries.length,
          itemBuilder: (_, i) => entries[i](),
        ),
      ),
    );
  }

  Widget _footer(TimelineState state) {
    if (state.loadMoreError != null) {
      return ErrorView(
        error: state.loadMoreError!,
        onRetry: () => ref.read(timelineProvider.notifier).loadMore(),
      );
    }
    if (state.hasMore) {
      // Built when scrolled near the end: fetch the next page.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(timelineProvider.notifier).loadMore();
      });
      return const Padding(padding: EdgeInsets.all(24), child: LoadingView());
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Text(
        state.posts.isEmpty
            ? 'Nothing here yet. Try another topic, or follow books and authors.'
            : "That's everything for now.",
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
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
    final topics = ref.watch(topicsProvider).value ?? kDefaultTopics;
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
