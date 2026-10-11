import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';

/// Plays a card's explainer video inline. It shows the poster until the reader
/// taps play, so nothing streams on cards they only skim. The credit, licence
/// and any health note are burned into the video itself.
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
                colors: VideoProgressColors(
                  playedColor: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      content = Semantics(
        button: true,
        label: 'Play animated explainer: ${widget.title}',
        child: InkWell(
          onTap: c == null || _failed ? _start : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                resolveMediaUrl(e.posterUrl),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              if (c != null && !_failed)
                const Center(child: CircularProgressIndicator())
              else
                const _PlayBadge(),
              if (_failed)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      "Couldn't load the video. Tap to try again.",
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        backgroundColor: Colors.black54,
                      ),
                    ),
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
              borderRadius: BorderRadius.circular(16),
              child: content,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${e.kind == 'film' ? 'Short film' : 'Animated explainer'} · '
          '${seconds < 60 ? '$seconds s' : '${(seconds / 60).toStringAsFixed(1)} min'}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 64,
      height: 64,
      decoration: const BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.play_arrow_rounded,
        color: Colors.white,
        size: 40,
      ),
    ),
  );
}
