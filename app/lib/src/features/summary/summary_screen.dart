import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../card/card_view.dart';
import '../listen/listen_controller.dart';
import '../listen/listen_follow.dart';
import '../post/post_view.dart';
import 'summary_controller.dart';
import 'summary_widgets.dart';

/// Reads a summary: one part per page with a progress bar (swipe sideways,
/// the arrow keys or the buttons turn the page), or every part on one long
/// page ("Read it all"). Opens where the reader stopped unless the link
/// names a part, and keeps their place as they go.
class SummaryScreen extends ConsumerStatefulWidget {
  const SummaryScreen({
    super.key,
    required this.summaryId,
    this.readAll = false,
    this.initialPart,
  });

  final String summaryId;
  final bool readAll;

  /// One-based part named in the link, or null to resume.
  final int? initialPart;

  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen> {
  late bool _all = widget.readAll;
  PageController? _pages;
  int _index = 0;
  int? _resumedAt;
  bool _savedEnd = false;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _pages?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Picks the opening part once the summary has loaded.
  void _open(SummaryDetail d) {
    if (_pages != null) return;
    final count = d.parts.length;
    final named = widget.initialPart;
    if (named != null) {
      _index = (named - 1).clamp(0, count - 1);
    } else {
      final local = ref.read(summaryPlacesProvider)[widget.summaryId];
      final p = bestProgress(d.summary.viewer, local);
      _index = p?.resumeIndex(count) ?? 0;
      if (_index > 0) _resumedAt = _index;
    }
    _pages = PageController(initialPage: _index);
    // Opening counts as starting; it never moves the saved place back.
    if (named != null || _index > 0 || _resumedAt == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _save(d));
    }
  }

  void _save(SummaryDetail d) {
    final last = d.parts.length - 1;
    ref
        .read(summaryPlacesProvider.notifier)
        .save(
          widget.summaryId,
          _index.clamp(0, last),
          finished: _index >= last,
        );
  }

  void _onPage(SummaryDetail d, int i) {
    final last = d.parts.length - 1;
    // Moving past a part counts as reading it.
    if (i > _index && _index <= last && ref.read(sessionProvider).signedIn) {
      ref.read(repositoryProvider).recordView(d.parts[_index].id);
    }
    setState(() {
      _index = i;
      _resumedAt = null;
    });
    _save(d);
  }

  void _turn(int delta, int pages) {
    final p = _pages;
    if (p == null || !p.hasClients) return;
    final target = _index + delta;
    if (target < 0 || target >= pages) return;
    p.animateToPage(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  /// On the long page, reaching the end finishes the summary.
  void _onScroll() {
    if (_savedEnd || !_all || !_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels < pos.maxScrollExtent - 200) return;
    final d = ref.read(summaryProvider(widget.summaryId)).value?.value;
    if (d == null) return;
    _savedEnd = true;
    ref
        .read(summaryPlacesProvider.notifier)
        .save(widget.summaryId, d.parts.length - 1, finished: true);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(summaryProvider(widget.summaryId));
    final d = async.value?.value;
    return Scaffold(
      appBar: AppBar(
        leading: exitLeading(context),
        title: Text(
          d?.summary.title ?? 'Summary',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (d != null) ...[
            IconButton(
              key: const ValueKey('summary-view'),
              tooltip: _all ? 'One at a time' : 'Read it all',
              icon: Icon(_all ? Icons.view_carousel_outlined : Icons.notes),
              onPressed: () => setState(() {
                _all = !_all;
                _index = _index.clamp(0, d.parts.length - 1);
                _pages?.dispose();
                _pages = PageController(initialPage: _index);
              }),
            ),
            IconButton(
              key: const ValueKey('summary-listen-all'),
              tooltip: 'Listen',
              icon: const Icon(Icons.headphones_outlined),
              onPressed: () => listenToSummary(
                context,
                ref,
                widget.summaryId,
                parts: d.parts,
                from: _all ? 0 : _index.clamp(0, d.parts.length - 1),
              ),
            ),
          ],
        ],
      ),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(summaryProvider(widget.summaryId)),
        ),
        data: (f) {
          final d = f.value;
          if (d.parts.isEmpty) {
            return const Center(child: Text('This summary has no parts yet.'));
          }
          _open(d);
          // Listen mode follows the part on screen (from the first on the
          // long page; not on the finished page).
          final last = d.parts.length - 1;
          return ListenFollow(
            target: !_all && _index > last
                ? null
                : ListenTarget.cards(
                    key: summaryListenKey(widget.summaryId),
                    cards: d.parts,
                    index: _all ? null : _index,
                  ),
            child: _all ? _allParts(d) : _oneAtATime(d),
          );
        },
      ),
    );
  }

  Widget _partHeader(BuildContext context, int i, int count) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
    child: Text(
      'Part ${i + 1} of $count',
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Candlelight.of(context).amberText,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _part(BuildContext context, SummaryDetail d, int i) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _partHeader(context, i, d.parts.length),
      IdeaCardView(
        card: d.parts[i],
        byline: AuthorByline.inline(card: d.parts[i]),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      ),
    ],
  );

  Widget _oneAtATime(SummaryDetail d) {
    final count = d.parts.length;
    final pages = count + 1; // the finished page
    final last = count - 1;
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _turn(1, pages),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _turn(-1, pages),
      },
      child: Focus(
        autofocus: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReadingWidth(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${d.summary.coverageLabel} · ${d.summary.meta}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Candlelight.of(context).muted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SummaryProgressLine(
                      key: const ValueKey('summary-progress'),
                      progress: SummaryProgress(
                        started: true,
                        position: _index.clamp(0, last),
                        finished: _index > last,
                      ),
                      parts: count,
                    ),
                    if (_resumedAt != null)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Picking up where you left off, at part ${_resumedAt! + 1}.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          TextButton(
                            onPressed: () => _pages?.jumpToPage(0),
                            child: const Text('Start over'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                key: const ValueKey('summary-pages'),
                controller: _pages,
                itemCount: pages,
                onPageChanged: (i) => _onPage(d, i),
                itemBuilder: (context, i) => i == count
                    ? SingleChildScrollView(
                        child: ReadingWidth(
                          child: _Finished(
                            summary: d.summary,
                            onRestart: () => _pages?.jumpToPage(0),
                            onReadAll: () => setState(() => _all = true),
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        key: ValueKey('summary-part-$i'),
                        child: ReadingWidth(child: _part(context, d, i)),
                      ),
              ),
            ),
            SafeArea(
              top: false,
              child: ReadingWidth(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                  child: Row(
                    children: [
                      OutlinedButton.icon(
                        key: const ValueKey('summary-previous'),
                        onPressed: _index == 0 ? null : () => _turn(-1, pages),
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('Previous'),
                      ),
                      const Spacer(),
                      if (_index <= last)
                        FilledButton.icon(
                          key: const ValueKey('summary-next'),
                          onPressed: () => _turn(1, pages),
                          icon: const Icon(Icons.chevron_right),
                          label: Text(_index == last ? 'Finish' : 'Next'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _allParts(SummaryDetail d) {
    final theme = Theme.of(context);
    final s = d.summary;
    return ListView.builder(
      key: const ValueKey('summary-all'),
      controller: _scroll,
      itemCount: d.parts.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) {
          return ReadingWidth(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SummaryCover(summary: s, large: true),
                  if (s.description.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(s.description, style: theme.textTheme.bodyLarge),
                  ],
                  if (s.source != null) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () => context.push('/sources/${s.source!.id}'),
                      child: Text(
                        s.coverage == 'key-ideas'
                            ? 'About the book: these are our own summaries'
                            : 'About the book, its credit and licence',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        if (i == d.parts.length + 1) {
          return ReadingWidth(
            child: _Finished(
              summary: s,
              onRestart: () => setState(() {
                _all = false;
                _index = 0;
                _pages?.dispose();
                _pages = PageController();
              }),
            ),
          );
        }
        return ReadingWidth(
          key: ValueKey('summary-all-part-${i - 1}'),
          child: Card(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: _part(context, d, i - 1),
          ),
        );
      },
    );
  }
}

class _Finished extends StatelessWidget {
  const _Finished({
    required this.summary,
    required this.onRestart,
    this.onReadAll,
  });
  final Summary summary;
  final VoidCallback onRestart;
  final VoidCallback? onReadAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('summary-finished'),
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      child: Column(
        children: [
          Text(
            "You've finished ${summary.title}",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: kDisplayFont,
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${summary.partCount} parts, about ${summary.minutes} minutes of big ideas.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton(
                onPressed: onRestart,
                child: const Text('Start again'),
              ),
              if (onReadAll != null)
                OutlinedButton(
                  onPressed: onReadAll,
                  child: const Text('Read it all'),
                ),
              if (summary.source != null)
                OutlinedButton(
                  onPressed: () =>
                      context.push('/sources/${summary.source!.id}'),
                  child: const Text('About the book'),
                ),
              FilledButton(
                onPressed: () => context.push('/summaries'),
                child: const Text('More summaries'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
