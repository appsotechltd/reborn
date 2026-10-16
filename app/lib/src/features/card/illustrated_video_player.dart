import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../theme.dart';
import '../listen/listen_controller.dart';
import 'explainer_player.dart';
import 'full_screen_video.dart';

/// How long one scene takes to fade into the next.
const kSceneFade = Duration(milliseconds: 800);

/// Where an illustrated video is at a moment: the scene showing, how far
/// through it the drift is (0..1), and how far the next scene has faded in
/// over it (0..1).
class SceneFrame {
  const SceneFrame(this.index, this.progress, this.fade);
  final int index;
  final double progress;
  final double fade;
}

/// Each of [count] scenes shows for an equal share of [total]; the next one
/// fades in over the last [fade] of each scene (never more than half of it).
SceneFrame sceneAt(
  int count,
  Duration total,
  Duration position, {
  Duration fade = kSceneFade,
}) {
  final totalMs = total.inMilliseconds;
  if (count <= 0 || totalMs <= 0) return const SceneFrame(0, 0, 0);
  final per = totalMs / count;
  final t = position.inMilliseconds.clamp(0, totalMs).toDouble();
  final index = (t / per).floor().clamp(0, count - 1);
  final into = t - index * per;
  final f = fade.inMilliseconds.toDouble().clamp(0.0, per / 2);
  var next = 0.0;
  if (index < count - 1 && f > 0 && into > per - f) {
    next = ((into - (per - f)) / f).clamp(0.0, 1.0);
  }
  return SceneFrame(index, (into / per).clamp(0.0, 1.0), next);
}

/// Plays a member card's illustrated video: the narration, with each scene
/// shown in turn for an equal share of it, drifting and zooming slowly and
/// cross-fading into the next. There is no on-screen text. The frame is a
/// dark 2:3 portrait in both colour modes, like the explainer films.
class IllustratedVideoPlayer extends ConsumerStatefulWidget {
  const IllustratedVideoPlayer({
    super.key,
    required this.video,
    required this.title,
    this.maxHeight = 520,
    this.fullScreen = false,
    this.startAt,
  });

  final CardVideo video;
  final String title;
  final double maxHeight;

  /// On its own full screen: starts playing at once (from [startAt]) and
  /// has no full-screen button of its own.
  final bool fullScreen;
  final Duration? startAt;

  @override
  ConsumerState<IllustratedVideoPlayer> createState() =>
      _IllustratedVideoPlayerState();
}

class _IllustratedVideoPlayerState extends ConsumerState<IllustratedVideoPlayer>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _audio;
  bool _failed = false;
  late final Ticker _ticker = createTicker((_) => _onFrame());

  // The plugin reports the position a few times a second; between reports
  // the picture moves on this clock so the drift stays smooth.
  Duration _base = Duration.zero;
  final _since = Stopwatch();

  @override
  void initState() {
    super.initState();
    if (widget.fullScreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _start(from: widget.startAt ?? Duration.zero);
      });
    }
    ref.listenManual(listenProvider.select((s) => s.playing), (was, now) {
      // Listen mode started: the video pauses.
      final c = _audio;
      if (now && was == false && c != null && c.value.isPlaying) {
        c.pause();
      }
    });
  }

  @override
  void didUpdateWidget(IllustratedVideoPlayer old) {
    super.didUpdateWidget(old);
    if (old.video.audioUrl != widget.video.audioUrl) {
      _audio?.dispose();
      _audio = null;
      _failed = false;
      _ticker.stop();
      _base = Duration.zero;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _audio?.dispose();
    super.dispose();
  }

  Duration get _total {
    final d = _audio?.value.duration ?? Duration.zero;
    return d > Duration.zero ? d : widget.video.duration;
  }

  Duration get _position {
    final c = _audio;
    if (c == null || !c.value.isPlaying) return _base;
    final p = _base + _since.elapsed;
    return p > _total ? _total : p;
  }

  void _onAudio() {
    final c = _audio;
    if (c == null || !mounted) return;
    final v = c.value;
    if (!v.isPlaying) {
      _since
        ..stop()
        ..reset();
      _base = v.position;
    } else if (!_since.isRunning ||
        (v.position - _position).abs() > const Duration(milliseconds: 250)) {
      // Follow the plugin when it disagrees with the local clock by much.
      _base = v.position;
      _since
        ..reset()
        ..start();
    }
    if (v.isPlaying && !_ticker.isActive) _ticker.start();
    if (!v.isPlaying && _ticker.isActive) _ticker.stop();
    setState(() {});
  }

  void _onFrame() {
    if (mounted) setState(() {});
  }

  void _pauseListening() {
    if (ref.read(listenProvider).playing) {
      ref.read(listenProvider.notifier).pause();
    }
  }

  Future<void> _start({Duration from = Duration.zero}) async {
    _pauseListening();
    final c = ref.read(videoControllerFactoryProvider)(
      Uri.parse(resolveMediaUrl(widget.video.audioUrl)),
    );
    setState(() {
      _audio = c;
      _failed = false;
    });
    for (final s in widget.video.scenes) {
      precacheImage(
        NetworkImage(resolveMediaUrl(s.url)),
        context,
        onError: (_, _) {},
      );
    }
    try {
      await c.initialize();
      if (!mounted || _audio != c) return;
      c.addListener(_onAudio);
      if (from > Duration.zero) {
        await c.seekTo(from);
        _base = from;
      }
      await c.play();
    } catch (_) {
      if (mounted && _audio == c) {
        setState(() {
          _audio = null;
          _failed = true;
        });
        c.dispose();
      }
    }
  }

  void _toggle() {
    final c = _audio;
    if (c == null) {
      _start();
      return;
    }
    if (!c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      _pauseListening();
      if (c.value.isCompleted || _position >= _total) {
        _base = Duration.zero;
        c.seekTo(Duration.zero);
      }
      c.play();
    }
  }

  /// Plays it on its own full screen from where it is; the inline player
  /// pauses meanwhile.
  Future<void> _openFullScreen() async {
    final from = _position >= _total ? Duration.zero : _position;
    final c = _audio;
    if (c != null && c.value.isPlaying) await c.pause();
    if (!mounted) return;
    await showFullScreenVideo(
      context,
      builder: (_) => IllustratedVideoPlayer(
        video: widget.video,
        title: widget.title,
        maxHeight: double.infinity,
        fullScreen: true,
        startAt: from,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    final c = _audio;
    final ready = c != null && c.value.isInitialized;
    final playing = ready && c.value.isPlaying;
    final loading = c != null && !ready;
    final total = _total;
    final position = _position;
    final frame = sceneAt(video.scenes.length, total, position);
    final scenes = video.scenes;
    final started = ready && (playing || position > Duration.zero);
    final share = total.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ColoredBox(
            color: CandlelightTokens.videoBase,
            child: Semantics(
              key: const ValueKey('illustrated-video'),
              button: true,
              label: _failed
                  ? "Couldn't play the video. Tap to try again."
                  : playing
                  ? 'Illustrated video: ${widget.title}. Tap to pause'
                  : 'Play illustrated video: ${widget.title}',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggle,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (scenes.isNotEmpty)
                      _Scene(
                        url: scenes[frame.index].url,
                        index: frame.index,
                        progress: started ? frame.progress : 0,
                      ),
                    if (frame.fade > 0 && frame.index + 1 < scenes.length)
                      Opacity(
                        opacity: frame.fade,
                        child: _Scene(
                          url: scenes[frame.index + 1].url,
                          index: frame.index + 1,
                          progress: 0,
                        ),
                      ),
                    if (!playing)
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: CandlelightTokens.videoFade,
                        ),
                      ),
                    if (loading)
                      const Center(
                        child: CircularProgressIndicator(
                          color: CandlelightTokens.amber,
                        ),
                      )
                    else if (_failed)
                      const Center(child: _Badge(icon: Icons.refresh_rounded))
                    else if (!playing)
                      Center(
                        child: _Badge(
                          key: const ValueKey('illustrated-play'),
                          icon: c != null && c.value.isCompleted
                              ? Icons.replay_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                    if (!widget.fullScreen)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: FullScreenButton(onPressed: _openFullScreen),
                      ),
                    if (ready)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          key: const ValueKey('illustrated-progress'),
                          value: share,
                          minHeight: 3,
                          color: CandlelightTokens.amber,
                          backgroundColor: const Color(0x33F2E8D8),
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

/// Directions the scenes drift in, in turn.
const _drifts = [
  Offset(-1, -0.6),
  Offset(1, -0.4),
  Offset(-0.8, 0.6),
  Offset(0.7, 0.5),
];

/// One illustration, slowly zooming (in on even scenes, out on odd ones)
/// and drifting as [progress] goes from 0 to 1.
class _Scene extends StatelessWidget {
  const _Scene({
    required this.url,
    required this.index,
    required this.progress,
  });
  final String url;
  final int index;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final p = Curves.easeInOut.transform(progress.clamp(0.0, 1.0));
    final scale = index.isEven ? 1.05 + 0.1 * p : 1.15 - 0.1 * p;
    final d = _drifts[index % _drifts.length];
    // Up to 2% of the frame either way, inside the 5% the zoom leaves.
    final shift = Offset(d.dx * 0.04 * (p - 0.5), d.dy * 0.04 * (p - 0.5));
    return ClipRect(
      child: Transform.scale(
        scale: scale,
        child: FractionalTranslation(
          translation: shift,
          child: Image.network(
            resolveMediaUrl(url),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({super.key, required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 64,
    height: 64,
    decoration: const BoxDecoration(
      color: CandlelightTokens.amber,
      shape: BoxShape.circle,
    ),
    child: Icon(icon, color: CandlelightTokens.onAmber, size: 40),
  );
}
