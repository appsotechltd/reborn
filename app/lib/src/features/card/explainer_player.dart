import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../theme.dart';
import '../listen/listen_controller.dart';
import 'full_screen_video.dart';
import 'video_autoplay.dart';

/// Makes the video controller for a URL; tests swap in a fake.
final videoControllerFactoryProvider =
    Provider<VideoPlayerController Function(Uri url)>(
      (_) => VideoPlayerController.networkUrl,
    );

/// Plays a card's explainer video inline.
///
/// On its own (the card screen) it shows the poster until the reader taps
/// play, so nothing streams on cards they only skim. Under a
/// [VideoAutoplayScope] (the home feed) it plays muted and looping while it
/// is the scope's active video, pauses otherwise, and a tap toggles sound.
/// The credit, licence and any health note are burned into the video itself;
/// there are no on-screen captions.
///
/// Films stay dark in both colour modes: a bottom fade with an amber kicker
/// and, beneath it, the Play pill with the duration beside it. The poster
/// art carries the title and topic at its top, so nothing is laid over it.
class ExplainerPlayer extends ConsumerStatefulWidget {
  const ExplainerPlayer({
    super.key,
    required this.explainer,
    required this.title,
    this.autoplayId,
    this.maxHeight = 440,
  });

  final Explainer explainer;
  final String title;

  /// The card id this player answers to under a [VideoAutoplayScope].
  final String? autoplayId;
  final double maxHeight;

  @override
  ConsumerState<ExplainerPlayer> createState() => _ExplainerPlayerState();
}

class _ExplainerPlayerState extends ConsumerState<ExplainerPlayer> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _wasPlaying = false;
  VideoAutoplay? _scope;
  bool _tickerOn = true;

  /// The reader paused the active video; cleared when it stops being active.
  bool _userPaused = false;

  bool get _autoplay => _scope != null && widget.autoplayId != null;

  bool get _shouldPlay =>
      _autoplay &&
      _tickerOn &&
      !_userPaused &&
      !_listening &&
      _scope!.playing == widget.autoplayId;

  /// Listen mode is playing: feed videos wait.
  bool _listening = false;

  /// Showing on its own full screen: the feed leaves it alone meanwhile.
  bool _fullScreen = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(listenProvider.select((s) => s.playing), (was, now) {
      _listening = now;
      if (was == null || !mounted) return;
      if (now) {
        final c = _controller;
        if (c != null && c.value.isInitialized && c.value.isPlaying) c.pause();
      }
      _scheduleSync();
      setState(() {});
    }, fireImmediately: true);
  }

  /// The reader started a video: Listen mode pauses.
  void _pauseListening() {
    if (!_listening) return;
    ref.read(listenProvider.notifier).pause();
    _listening = false;
  }

  void _toggleMuted() {
    if (_scope!.muted) _pauseListening();
    _scope!.toggleMuted();
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = VideoAutoplayScope.maybeOf(context);
    if (scope != _scope) {
      _detach();
      _scope = scope;
      scope?.addListener(_onScope);
      final id = widget.autoplayId;
      if (scope != null && id != null) scope.attach(id, context);
    }
    // Paused when its route or tab is hidden.
    _tickerOn = TickerMode.valuesOf(context).enabled;
    _scheduleSync();
  }

  @override
  void didUpdateWidget(ExplainerPlayer old) {
    super.didUpdateWidget(old);
    if (old.autoplayId != widget.autoplayId) {
      final id = old.autoplayId;
      if (id != null) _scope?.detach(id, context);
      final now = widget.autoplayId;
      if (now != null) _scope?.attach(now, context);
    }
    if (old.explainer.videoUrl != widget.explainer.videoUrl) _reset();
    _scheduleSync();
  }

  @override
  void dispose() {
    _detach();
    _controller?.dispose();
    super.dispose();
  }

  void _detach() {
    _scope?.removeListener(_onScope);
    final id = widget.autoplayId;
    if (id != null) _scope?.detach(id, context);
  }

  void _reset() {
    _controller?.dispose();
    _controller = null;
    _failed = false;
    _wasPlaying = false;
  }

  bool _syncScheduled = false;

  /// Syncs after this frame: play() and pause() notify listeners at once,
  /// which must not happen mid-build.
  void _scheduleSync() {
    if (_syncScheduled || !_autoplay) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      _sync();
    });
  }

  void _onScope() {
    _sync();
    if (mounted) setState(() {});
  }

  /// Brings the player in line with the scope: play the active video (with
  /// the shared sound setting), pause the rest.
  void _sync() {
    if (!mounted || !_autoplay || _fullScreen) return;
    if (_scope!.active != widget.autoplayId) _userPaused = false;
    final c = _controller;
    if (_shouldPlay) {
      if (c == null) {
        if (!_failed) _start();
        return;
      }
      if (!c.value.isInitialized) return;
      c.setVolume(_scope!.muted ? 0 : 1);
      if (!c.value.isPlaying) c.play();
    } else if (c != null && c.value.isInitialized) {
      if (c.value.isPlaying) c.pause();
      c.setVolume(_scope!.muted ? 0 : 1);
    }
  }

  Future<void> _start() async {
    if (!_autoplay) _pauseListening();
    final c = ref.read(videoControllerFactoryProvider)(
      Uri.parse(resolveMediaUrl(widget.explainer.videoUrl)),
    );
    setState(() {
      _controller = c;
      _failed = false;
    });
    try {
      await c.initialize();
      if (!mounted || _controller != c) return;
      c.addListener(_onTick);
      if (_autoplay) {
        await c.setLooping(true);
        await c.setVolume(_scope!.muted ? 0 : 1);
        if (_shouldPlay) await c.play();
      } else {
        await c.play();
      }
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted && _controller == c) setState(() => _failed = true);
    }
  }

  void _onTick() {
    final c = _controller;
    if (c == null || !mounted) return;
    // Rebuild on play/pause and at the end so the overlay follows.
    final v = c.value;
    if (v.isPlaying != _wasPlaying || v.isCompleted) {
      _wasPlaying = v.isPlaying;
      setState(() {});
    }
  }

  void _toggle() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (!c.value.isPlaying) _pauseListening();
    if (_autoplay) {
      // Pausing the feed's video sticks until it scrolls away.
      _userPaused = c.value.isPlaying;
      if (!_userPaused) _scope!.setActive(widget.autoplayId);
      _sync();
      if (_userPaused) c.pause();
      setState(() {});
      return;
    }
    setState(() {
      if (c.value.isPlaying) {
        c.pause();
      } else {
        if (c.value.isCompleted) c.seekTo(Duration.zero);
        c.play();
      }
    });
  }

  /// Plays the video on its own full screen, with sound (the reader chose
  /// to watch it). Back in the feed it follows the feed's sound setting again.
  Future<void> _openFullScreen() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    _pauseListening();
    _fullScreen = true;
    _userPaused = false;
    await c.setVolume(1);
    if (!c.value.isPlaying) {
      if (c.value.isCompleted) await c.seekTo(Duration.zero);
      await c.play();
    }
    if (!mounted) return;
    await showFullScreenVideo(
      context,
      builder: (_) => FullScreenFilm(controller: c, title: widget.title),
    );
    if (!mounted) return;
    _fullScreen = false;
    if (_autoplay) {
      _sync();
    }
    setState(() {});
  }

  void _tapPoster() {
    _pauseListening();
    if (_autoplay) {
      _userPaused = false;
      _failed = false;
      _scope!.setActive(widget.autoplayId);
      if (_controller == null) _start();
      return;
    }
    _start();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = widget.explainer;
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    final seconds = e.durationS.round();
    final kicker = e.kind == 'film' ? 'Short film' : 'Animated explainer';
    final duration =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

    final Widget content;
    if (ready && _autoplay) {
      final muted = _scope!.muted;
      final playing = c.value.isPlaying;
      content = Stack(
        fit: StackFit.expand,
        children: [
          Semantics(
            key: const ValueKey('video-surface'),
            button: true,
            label: muted
                ? 'Video: ${widget.title}. Tap to turn sound on'
                : 'Video: ${widget.title}. Tap to mute',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleMuted,
              child: VideoPlayer(c),
            ),
          ),
          if (!playing && _userPaused) const IgnorePointer(child: _PlayBadge()),
          Align(
            alignment: Alignment.bottomCenter,
            child: VideoProgressIndicator(
              c,
              allowScrubbing: false,
              colors: _progressColors,
            ),
          ),
          // Top right, clear of the credit burned into the bottom of the film.
          Positioned(
            right: 8,
            top: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilmButton(
                  key: const ValueKey('video-play-pause'),
                  tooltip: playing ? 'Pause video' : 'Play video',
                  icon: playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  onPressed: _toggle,
                ),
                const SizedBox(width: 8),
                FilmButton(
                  key: const ValueKey('video-mute'),
                  tooltip: muted ? 'Turn sound on' : 'Mute',
                  icon: muted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  onPressed: _toggleMuted,
                ),
                const SizedBox(width: 8),
                FullScreenButton(onPressed: _openFullScreen),
              ],
            ),
          ),
        ],
      );
    } else if (ready) {
      content = GestureDetector(
        onTap: _toggle,
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoPlayer(c),
            if (!c.value.isPlaying) const _PlayBadge(),
            Align(
              alignment: Alignment.bottomCenter,
              child: VideoProgressIndicator(
                c,
                allowScrubbing: true,
                colors: _progressColors,
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: FullScreenButton(onPressed: _openFullScreen),
            ),
          ],
        ),
      );
    } else {
      content = Semantics(
        button: true,
        label: _failed
            ? "Couldn't load the video. Tap to try again."
            : 'Play animated explainer: ${widget.title}',
        // The label already says what the caption shows.
        excludeSemantics: true,
        child: InkWell(
          onTap: c == null || _failed ? _tapPoster : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                resolveMediaUrl(e.posterUrl),
                fit: BoxFit.cover,
                // The poster art prints its own title and topic; the card's
                // title is written out above the player.
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: CandlelightTokens.videoBase),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: CandlelightTokens.videoFade,
                ),
              ),
              if (c != null && !_failed)
                const Center(
                  child: CircularProgressIndicator(
                    color: CandlelightTokens.amber,
                  ),
                ),
              // Below the poster's printed title and above its printed
              // credit line, so neither is covered.
              if (_failed)
                Align(
                  alignment: const Alignment(0, 0.45),
                  child: Container(
                    key: const ValueKey('video-failed'),
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xE614110E),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      "Couldn't load the video. Tap to try again.",
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: kFilmInk,
                      ),
                    ),
                  ),
                )
              else
                // Play with the duration beside it, in the bottom band, clear
                // of the poster's own title and topic label (as on the web).
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Bright amber is fine here: the film is always dark.
                      CategoryTag(kicker, color: CandlelightTokens.amber),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (c == null) const _PlayPill(),
                          const Spacer(),
                          _DurationPill(text: duration),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          child: AspectRatio(
            aspectRatio: e.aspectRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ColoredBox(
                color: CandlelightTokens.videoBase,
                child: content,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

const _progressColors = VideoProgressColors(
  playedColor: CandlelightTokens.amber,
  bufferedColor: Color(0x66F2E8D8),
  backgroundColor: Color(0x33F2E8D8),
);

/// The amber "Play" pill in the poster's bottom row.
class _PlayPill extends StatelessWidget {
  const _PlayPill();

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('video-play'),
    constraints: const BoxConstraints(minHeight: 44),
    padding: const EdgeInsets.fromLTRB(12, 6, 18, 6),
    decoration: const ShapeDecoration(
      color: CandlelightTokens.amber,
      shape: StadiumBorder(),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.play_arrow_rounded,
          color: CandlelightTokens.onAmber,
          size: 22,
        ),
        SizedBox(width: 4),
        Text(
          'Play',
          style: TextStyle(
            fontFamily: kBodyFont,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: CandlelightTokens.onAmber,
          ),
        ),
      ],
    ),
  );
}

class _DurationPill extends StatelessWidget {
  const _DurationPill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
    decoration: const ShapeDecoration(
      color: Color(0xB314110E),
      shape: StadiumBorder(),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: CandlelightTokens.amber,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontFamily: kBodyFont,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: kFilmInk,
          ),
        ),
      ],
    ),
  );
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 64,
      height: 64,
      decoration: const BoxDecoration(
        color: CandlelightTokens.amber,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.play_arrow_rounded,
        color: CandlelightTokens.onAmber,
        size: 40,
      ),
    ),
  );
}

/// An explainer on its own full screen: the same playback (it carries on
/// where it was), the whole film fitted to the screen, tap to pause or play,
/// and a progress bar to scrub.
class FullScreenFilm extends StatefulWidget {
  const FullScreenFilm({
    super.key,
    required this.controller,
    required this.title,
  });
  final VideoPlayerController controller;
  final String title;

  @override
  State<FullScreenFilm> createState() => _FullScreenFilmState();
}

class _FullScreenFilmState extends State<FullScreenFilm> {
  bool _wasPlaying = false;

  @override
  void initState() {
    super.initState();
    _wasPlaying = widget.controller.value.isPlaying;
    widget.controller.addListener(_onTick);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    final playing = widget.controller.value.isPlaying;
    if (playing != _wasPlaying && mounted) {
      setState(() => _wasPlaying = playing);
    }
  }

  void _toggle() {
    final c = widget.controller;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      if (c.value.isCompleted) c.seekTo(Duration.zero);
      c.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final playing = c.value.isPlaying;
    return Semantics(
      button: true,
      label: playing
          ? 'Video: ${widget.title}. Tap to pause'
          : 'Video: ${widget.title}. Tap to play',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: c.value.aspectRatio,
                child: VideoPlayer(c),
              ),
            ),
            if (!playing) const Center(child: _PlayBadge()),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: VideoProgressIndicator(
                    c,
                    allowScrubbing: true,
                    colors: _progressColors,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
