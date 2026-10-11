import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../theme.dart';

/// Plays a card's explainer video inline. It shows the poster until the reader
/// taps play, so nothing streams on cards they only skim. The credit, licence
/// and any health note are burned into the video itself.
///
/// Films stay dark in both colour modes: a bottom fade, an amber kicker, the
/// title in white Fraunces and a duration pill.
class ExplainerPlayer extends StatefulWidget {
  const ExplainerPlayer({
    super.key,
    required this.explainer,
    required this.title,
    this.maxHeight = 440,
  });

  final Explainer explainer;
  final String title;
  final double maxHeight;

  @override
  State<ExplainerPlayer> createState() => _ExplainerPlayerState();
}

class _ExplainerPlayerState extends State<ExplainerPlayer> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void didUpdateWidget(ExplainerPlayer old) {
    super.didUpdateWidget(old);
    if (old.explainer.videoUrl != widget.explainer.videoUrl) _reset();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _reset() {
    _controller?.dispose();
    _controller = null;
    _failed = false;
  }

  Future<void> _start() async {
    final c = VideoPlayerController.networkUrl(
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
      await c.play();
      setState(() {});
    } catch (_) {
      if (mounted && _controller == c) setState(() => _failed = true);
    }
  }

  void _onTick() {
    final c = _controller;
    if (c == null || !mounted) return;
    // Rebuild on play/pause and at the end so the overlay follows.
    final v = c.value;
    if (v.isCompleted || !v.isPlaying) setState(() {});
  }

  void _toggle() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    setState(() {
      if (c.value.isPlaying) {
        c.pause();
      } else {
        if (c.value.isCompleted) c.seekTo(Duration.zero);
        c.play();
      }
    });
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
    if (ready) {
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
                colors: const VideoProgressColors(
                  playedColor: CandlelightTokens.amber,
                  bufferedColor: Color(0x66F2E8D8),
                  backgroundColor: Color(0x33F2E8D8),
                ),
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
          onTap: c == null || _failed ? _start : null,
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
