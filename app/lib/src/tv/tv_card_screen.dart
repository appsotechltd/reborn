import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../data/providers.dart';
import '../features/card/card_view.dart';
import '../features/card/explainer_player.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'tv_mode.dart';

/// One idea, big, on a TV: topic, title and book on the left with Play and
/// Back; the card's text on the right, scrolled with up and down once it
/// has focus. Back on the remote returns to the rows.
class TvCardScreen extends ConsumerStatefulWidget {
  const TvCardScreen({super.key, required this.cardId, this.initial});
  final String cardId;
  final Post? initial;

  @override
  ConsumerState<TvCardScreen> createState() => _TvCardScreenState();
}

class _TvCardScreenState extends ConsumerState<TvCardScreen> {
  final _scroll = ScrollController();
  final _bodyFocus = FocusNode(debugLabel: 'tv-card-body');
  final _readFocus = FocusNode(debugLabel: 'tv-read');
  bool _bodyFocused = false;
  bool _recorded = false;

  @override
  void initState() {
    super.initState();
    OwnFocusHighlight.mark(_bodyFocus);
    final initial = widget.initial;
    if (initial != null) Future.microtask(() => _opened(initial.card));
  }

  @override
  void dispose() {
    _scroll.dispose();
    _bodyFocus.dispose();
    _readFocus.dispose();
    super.dispose();
  }

  void _opened(IdeaCard card) {
    if (_recorded || !mounted) return;
    _recorded = true;
    final repo = ref.read(repositoryProvider);
    repo.rememberCard(card);
    if (ref.read(sessionProvider).signedIn) repo.recordView(card.id);
  }

  KeyEventResult _onBodyKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // The first Back from the text returns to the buttons; the next one
    // leaves the page.
    if (e is KeyDownEvent &&
        (e.logicalKey == LogicalKeyboardKey.escape ||
            e.logicalKey == LogicalKeyboardKey.goBack ||
            e.logicalKey == LogicalKeyboardKey.browserBack)) {
      _readFocus.requestFocus();
      return KeyEventResult.handled;
    }
    final down = e.logicalKey == LogicalKeyboardKey.arrowDown;
    final up = e.logicalKey == LogicalKeyboardKey.arrowUp;
    if (!down && !up) return KeyEventResult.ignored;
    if (!_scroll.hasClients) return KeyEventResult.handled;
    final p = _scroll.position;
    final step = p.viewportDimension * 0.4;
    final to = (p.pixels + (down ? step : -step)).clamp(
      p.minScrollExtent,
      p.maxScrollExtent,
    );
    _scroll.animateTo(
      to,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final fetched = ref.watch(postProvider(widget.cardId));
    ref.listen(postProvider(widget.cardId), (_, next) {
      final v = next.value;
      if (v != null && !v.offline) _opened(v.value.card);
    });
    final post = fetched.value?.value ?? widget.initial;
    return Scaffold(
      body: post == null
          ? fetched.hasError
                ? ErrorView(
                    error: fetched.error!,
                    onRetry: () => ref.invalidate(postProvider(widget.cardId)),
                  )
                : const LoadingView()
          : _layout(context, post.card),
    );
  }

  Widget _layout(BuildContext context, IdeaCard card) {
    final theme = Theme.of(context);
    final c = Candlelight.of(context);
    final topic = ref.watch(topicNamesProvider)[card.topic] ?? card.topic;
    final video = card.explainer;
    final source = [
      card.source.title,
      ...card.source.authors,
    ].where((s) => s.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 4,
            child: FocusTraversalGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CategoryTag(topic),
                  const SizedBox(height: 10),
                  Text(
                    card.title,
                    key: const ValueKey('tv-card-title'),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    source,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: c.amberText,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Wrap(
                    spacing: 14,
                    runSpacing: 12,
                    children: [
                      if (video != null)
                        FilledButton.icon(
                          key: const ValueKey('tv-play'),
                          autofocus: true,
                          onPressed: () => context.push(
                            '/tv/video/${Uri.encodeComponent(card.id)}',
                            extra: card,
                          ),
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Play video'),
                        ),
                      OutlinedButton.icon(
                        key: const ValueKey('tv-read'),
                        focusNode: _readFocus,
                        autofocus: video == null,
                        onPressed: () => _bodyFocus.requestFocus(),
                        icon: const Icon(Icons.chrome_reader_mode_outlined),
                        label: const Text('Read'),
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('tv-back'),
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Back'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 32),
          Expanded(
            flex: 5,
            child: Focus(
              focusNode: _bodyFocus,
              onKeyEvent: _onBodyKey,
              onFocusChange: (f) => setState(() => _bodyFocused = f),
              child: AnimatedContainer(
                key: const ValueKey('tv-card-body'),
                duration: const Duration(milliseconds: 160),
                decoration: BoxDecoration(
                  color: theme.cardTheme.color ?? theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _bodyFocused ? CandlelightTokens.amber : c.line,
                    width: _bodyFocused ? 3 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: IdeaCardView(
                    card: card,
                    showActions: false,
                    showVideo: false,
                    // The topic already heads the left column.
                    showTopic: false,
                    padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A card's explainer video filling the screen. Select (or Enter, or the
/// remote's play/pause key) plays and pauses; Back leaves.
class TvVideoScreen extends ConsumerStatefulWidget {
  const TvVideoScreen({super.key, required this.card});
  final IdeaCard card;

  @override
  ConsumerState<TvVideoScreen> createState() => _TvVideoScreenState();
}

class _TvVideoScreenState extends ConsumerState<TvVideoScreen> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final video = widget.card.explainer;
    if (video == null) return;
    final c = ref.read(videoControllerFactoryProvider)(
      Uri.parse(resolveMediaUrl(video.videoUrl)),
    );
    _controller = c;
    c.addListener(_onTick);
    c
        .initialize()
        .then((_) async {
          if (!mounted) return;
          await c.play();
          if (mounted) setState(() {});
        })
        .catchError((Object _) {
          if (mounted) setState(() => _failed = true);
        });
  }

  bool _wasPlaying = false;
  void _onTick() {
    final playing = _controller?.value.isPlaying ?? false;
    if (playing != _wasPlaying && mounted) {
      _wasPlaying = playing;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  void _toggle() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      if (c.value.isCompleted) c.seekTo(Duration.zero);
      c.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    final playing = ready && c.value.isPlaying;
    final video = widget.card.explainer;
    return Scaffold(
      backgroundColor: CandlelightTokens.videoBase,
      body: Actions(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _toggle();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          debugLabel: 'tv-video',
          child: GestureDetector(
            onTap: _toggle,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: ready
                      ? AspectRatio(
                          aspectRatio: c.value.aspectRatio,
                          child: VideoPlayer(c),
                        )
                      : video == null
                      ? const SizedBox()
                      : Image.network(
                          resolveMediaUrl(video.posterUrl),
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const SizedBox(),
                        ),
                ),
                if (_failed)
                  LayoutBuilder(
                    // Below the poster's printed title, above its credit.
                    builder: (context, box) => Align(
                      alignment: const Alignment(0, 0.5),
                      child: ConstrainedBox(
                        // Kept inside the poster (shown at its own shape,
                        // centred) and wrapped: a dark band reaching past the
                        // poster vanishes into the dark screen, leaving its
                        // text looking as if it overflowed.
                        constraints: BoxConstraints(
                          maxWidth: math.min(
                            520,
                            math.min(
                              box.maxWidth,
                              box.maxHeight * (video?.aspectRatio ?? 16 / 9),
                            ),
                          ),
                        ),
                        child: Container(
                          key: const ValueKey('tv-video-failed'),
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: CandlelightTokens.videoBase.withValues(
                              alpha: 0.92,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "This video couldn't be played here.",
                                textAlign: TextAlign.center,
                                softWrap: true,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: const Color(0xFFF2E8D8),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Press Back to leave.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: const Color(0xFFD9CDBA),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!playing && !_failed)
                  Container(
                    key: const ValueKey('tv-video-paused'),
                    color: const Color(0x8014110E),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          ready ? Icons.play_circle_fill : Icons.hourglass_top,
                          size: 88,
                          color: CandlelightTokens.amber,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.card.title,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: const Color(0xFFF2E8D8),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          ready
                              ? 'OK to play · Back to leave'
                              : 'Loading… · Back to leave',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFFD9CDBA),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
