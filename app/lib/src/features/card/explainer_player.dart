import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../theme.dart';
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
/// Films stay dark in both colour modes: a bottom fade, an amber kicker, the
/// title in white Fraunces and a duration pill.
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
      _scope!.playing == widget.autoplayId;

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
    if (!mounted || !_autoplay) return;
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

  void _tapPoster() {
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
              onTap: _scope!.toggleMuted,
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
                _FilmButton(
                  key: const ValueKey('video-play-pause'),
                  tooltip: playing ? 'Pause video' : 'Play video',
                  icon: playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  onPressed: _toggle,
                ),
                const SizedBox(width: 8),
                _FilmButton(
                  key: const ValueKey('video-mute'),
                  tooltip: muted ? 'Turn sound on' : 'Mute',
                  icon: muted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  onPressed: _scope!.toggleMuted,
                ),
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
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: CandlelightTokens.videoBase),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: CandlelightTokens.videoFade,
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: _DurationPill(text: duration),
              ),
              if (c != null && !_failed)
                const Center(
                  child: CircularProgressIndicator(
                    color: CandlelightTokens.amber,
                  ),
                )
              else
                const _PlayBadge(),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _failed
                    ? Text(
                        "Couldn't load the video. Tap to try again.",
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _filmInk,
                        ),
                      )
                    : _FilmCaption(kicker: kicker, title: widget.title),
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

/// A small round control on the film (mute, pause): dark glass, white icon.
class _FilmButton extends StatelessWidget {
  const _FilmButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 20),
    color: _filmInk,
    style: IconButton.styleFrom(
      backgroundColor: const Color(0xB314110E),
      minimumSize: const Size(40, 40),
      fixedSize: const Size(40, 40),
      padding: EdgeInsets.zero,
    ),
  );
}

/// Text on films is white-ish whatever the app's mode.
const _filmInk = Color(0xFFFFFFFF);

class _FilmCaption extends StatelessWidget {
  const _FilmCaption({required this.kicker, required this.title});
  final String kicker;
  final String title;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      // Bright amber is fine here: the film is always dark.
      CategoryTag(kicker, color: CandlelightTokens.amber),
      const SizedBox(height: 6),
      Text(
        title,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: kDisplayFont,
          fontWeight: FontWeight.w600,
          fontSize: 20,
          height: 1.15,
          letterSpacing: -0.2,
          color: _filmInk,
          shadows: [Shadow(color: Color(0x8014110E), blurRadius: 12)],
        ),
      ),
    ],
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
            color: _filmInk,
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
