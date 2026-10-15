import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';
import '../card/card_view.dart';
import '../daily/daily_screen.dart';
import 'feed_controller.dart';

/// One idea per page, swiped vertically (opened from the timeline).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _pages = PageController();
  final _viewed = <String>{};

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _onPage(int index, FeedState feed) {
    if (index < feed.cards.length) {
      final card = feed.cards[index];
      if (ref.read(sessionProvider).signedIn && _viewed.add(card.id)) {
        ref.read(repositoryProvider).recordView(card.id);
      }
    }
    if (index >= feed.cards.length - 3) {
      ref.read(feedProvider.notifier).loadMore();
    }
  }

  bool _turning = false;

  /// Inner card scroll views use clamping physics; overscrolling past either
  /// end turns the page, so long cards scroll and short ones page.
  Future<void> _turnPage(int delta) async {
    if (_turning || !_pages.hasClients) return;
    final current = _pages.page?.round() ?? 0;
    final target = current + delta;
    if (target < 0) return;
    _turning = true;
    await _pages.animateToPage(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
    _turning = false;
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider);
    ref.listen(feedFilterProvider, (_, _) {
      if (_pages.hasClients) _pages.jumpToPage(0);
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('Swipe ideas'),
        actions: const [
          ThemeToggleButton(),
          ProfileMenuButton(),
          SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          const ReadingWidth(child: DailyBanner()),
          const _TopicChips(),
          Expanded(
            child: feed.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.invalidate(feedProvider),
              ),
              data: (state) {
                if (state.cards.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No ideas here yet. Try another topic.'),
                    ),
                  );
                }
                if (_viewed.isEmpty && state.cards.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _onPage(0, state);
                  });
                }
                return PageView.builder(
                  controller: _pages,
                  scrollDirection: Axis.vertical,
                  itemCount:
                      state.cards.length +
                      (state.hasMore || state.loadingMore ? 1 : 0),
                  onPageChanged: (i) => _onPage(i, state),
                  itemBuilder: (context, i) {
                    if (i >= state.cards.length) {
                      if (state.loadMoreError != null) {
                        return ErrorView(
                          error: state.loadMoreError!,
                          onRetry: () =>
                              ref.read(feedProvider.notifier).loadMore(),
                        );
                      }
                      return const LoadingView();
                    }
                    return _FeedPage(
                      index: i,
                      total: state.cards.length,
                      state: state,
                      onOverscroll: _turnPage,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedPage extends StatelessWidget {
  const _FeedPage({
    required this.index,
    required this.total,
    required this.state,
    required this.onOverscroll,
  });
  final int index;
  final int total;
  final FeedState state;
  final void Function(int delta) onOverscroll;

  @override
  Widget build(BuildContext context) {
    final card = state.cards[index];
    return NotificationListener<OverscrollNotification>(
      onNotification: (n) {
        if (n.overscroll > 4) onOverscroll(1);
        if (n.overscroll < -4) onOverscroll(-1);
        return true;
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        child: ReadingWidth(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Card(
              child: Column(
                children: [
                  IdeaCardView(card: card),
                  if (index == 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.keyboard_arrow_up,
                            size: 18,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          Text(
                            'Swipe up for the next idea',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
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

class _TopicChips extends ConsumerWidget {
  const _TopicChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topics = ref.watch(topicsProvider).value ?? kDefaultTopics;
    final selected = ref.watch(feedFilterProvider);
    final notifier = ref.read(feedFilterProvider.notifier);
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
