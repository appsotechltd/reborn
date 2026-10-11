import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../theme.dart';
import 'listen_controller.dart';

/// "1:05".
String formatListenTime(Duration d) {
  final s = d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// "1.25×".
String formatSpeed(double speed) {
  final t = speed == speed.roundToDouble()
      ? speed.toStringAsFixed(0)
      : speed.toString();
  return '$t×';
}

/// Docked above the bottom tab bar (or under the tab on wide windows)
/// while Listen mode is on: the card title, play/pause and next. Tapping it
/// opens the Now listening screen.
class ListenMiniPlayer extends ConsumerWidget {
  const ListenMiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(listenProvider);
    final post = s.current;
    if (!s.active || post == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final c = Candlelight.of(context);
    final controller = ref.read(listenProvider.notifier);
    final d = s.duration;
    final progress = d == null || d == Duration.zero
        ? 0.0
        : (s.position.inMilliseconds / d.inMilliseconds).clamp(0.0, 1.0);
    return Material(
      key: const ValueKey('listen-mini-player'),
      color: c.inset,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: progress,
            minHeight: 2,
            backgroundColor: c.line,
            color: c.amber,
            semanticsLabel: 'Listening progress',
          ),
          InkWell(
            onTap: () => context.push('/listen'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
              child: Row(
                children: [
                  Icon(Icons.headphones, size: 20, color: c.amberText),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Semantics(
                      button: true,
                      label:
                          'Now listening: ${post.card.title}. '
                          'Open the player',
                      excludeSemantics: true,
                      child: Text(
                        post.card.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('listen-mini-toggle'),
                    tooltip: s.playing ? 'Pause' : 'Play',
                    onPressed: controller.toggle,
                    icon: Icon(
                      s.playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('listen-mini-next'),
                    tooltip: 'Next idea',
                    onPressed: s.hasNext ? controller.next : null,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The full Now listening screen: what's playing, a progress bar to scrub,
/// the controls, speed, the sleep timer and a link to the card. Only the
/// title is shown while it plays: no captions or transcript.
class NowListeningScreen extends ConsumerWidget {
  const NowListeningScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(listenProvider);
    final post = s.current;
    final controller = ref.read(listenProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close player',
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: const Text('Now listening'),
        actions: [
          if (s.active)
            IconButton(
              key: const ValueKey('listen-stop'),
              tooltip: 'Stop listening',
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: () {
                controller.stop();
                if (context.canPop()) context.pop();
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: post == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nothing is playing.'),
              ),
            )
          : SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: _NowPlaying(state: s),
                  ),
                ),
              ),
            ),
    );
  }
}

class _NowPlaying extends ConsumerWidget {
  const _NowPlaying({required this.state});
  final ListenState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = state;
    final card = s.current!.card;
    final theme = Theme.of(context);
    final c = Candlelight.of(context);
    final controller = ref.read(listenProvider.notifier);
    final topic = ref.watch(topicNamesProvider)[card.topic] ?? card.topic;
    final voice = s.deviceVoice
        ? 'Device voice'
        : (card.audio!.voiceName.isNotEmpty
              ? 'Read by ${card.audio!.voiceName}'
              : 'Recorded reading');
    final muted = theme.textTheme.bodyMedium?.copyWith(color: c.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: c.inset,
              shape: BoxShape.circle,
              border: Border.all(color: c.line),
            ),
            child: Icon(Icons.headphones, size: 52, color: c.amberText),
          ),
        ),
        const SizedBox(height: 24),
        if (topic.isNotEmpty)
          Text(
            topic.toUpperCase(),
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              color: c.amberText,
              letterSpacing: 1.2,
            ),
          ),
        const SizedBox(height: 8),
        Semantics(
          header: true,
          child: Text(
            card.title,
            key: const ValueKey('listen-title'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 8),
        Text(subtitleOf(card), textAlign: TextAlign.center, style: muted),
        const SizedBox(height: 4),
        Text(
          voice,
          key: const ValueKey('listen-voice'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: c.muted),
        ),
        const SizedBox(height: 20),
        _Scrubber(state: s),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              key: const ValueKey('listen-back10'),
              tooltip: 'Back 10 seconds',
              iconSize: 30,
              onPressed: s.deviceVoice ? null : controller.back10,
              icon: const Icon(Icons.replay_10_rounded),
            ),
            IconButton(
              key: const ValueKey('listen-previous'),
              tooltip: 'Previous idea, or start again',
              iconSize: 34,
              onPressed: controller.previous,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: s.playing ? 'Pause' : 'Play',
              excludeSemantics: true,
              child: IconButton.filled(
                key: const ValueKey('listen-toggle'),
                iconSize: 40,
                style: IconButton.styleFrom(
                  backgroundColor: c.amber,
                  foregroundColor: c.onAmber,
                  fixedSize: const Size(72, 72),
                ),
                onPressed: controller.toggle,
                icon: s.loading
                    ? SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: c.onAmber,
                        ),
                      )
                    : Icon(
                        s.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const ValueKey('listen-next'),
              tooltip: 'Next idea',
              iconSize: 34,
              onPressed: s.hasNext ? controller.next : null,
              icon: const Icon(Icons.skip_next_rounded),
            ),
            // Balances the back-10 button.
            const SizedBox(width: 48),
          ],
        ),
        if (s.finished)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              "That's everything for now.",
              textAlign: TextAlign.center,
              style: muted,
            ),
          ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Semantics(
              button: true,
              label: 'Speed ${formatSpeed(s.speed)}. Change speed',
              excludeSemantics: true,
              child: OutlinedButton.icon(
                key: const ValueKey('listen-speed'),
                onPressed: controller.cycleSpeed,
                icon: const Icon(Icons.speed),
                label: Text(formatSpeed(s.speed)),
              ),
            ),
            _SleepButton(state: s),
            OutlinedButton.icon(
              key: const ValueKey('listen-open-card'),
              onPressed: () => context.push(
                '/cards/${Uri.encodeComponent(card.id)}',
                extra: card,
              ),
              icon: const Icon(Icons.article_outlined),
              label: const Text('Open card'),
            ),
          ],
        ),
      ],
    );
  }
}

/// The progress bar; drag to scrub (recordings only: the device voice
/// can't jump).
class _Scrubber extends ConsumerStatefulWidget {
  const _Scrubber({required this.state});
  final ListenState state;

  @override
  ConsumerState<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends ConsumerState<_Scrubber> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = Candlelight.of(context);
    final d = s.duration ?? Duration.zero;
    final total = d.inMilliseconds.toDouble();
    final at = (_dragging ?? s.position.inMilliseconds.toDouble()).clamp(
      0.0,
      total <= 0 ? 0.0 : total,
    );
    final canSeek = !s.deviceVoice && total > 0;
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: c.muted);
    return Column(
      children: [
        Slider(
          key: const ValueKey('listen-scrubber'),
          value: at,
          max: total <= 0 ? 1 : total,
          activeColor: c.amber,
          inactiveColor: c.line,
          semanticFormatterCallback: (v) =>
              '${formatListenTime(Duration(milliseconds: v.round()))} '
              'of ${formatListenTime(d)}',
          onChanged: canSeek ? (v) => setState(() => _dragging = v) : null,
          onChangeEnd: canSeek
              ? (v) {
                  setState(() => _dragging = null);
                  ref
                      .read(listenProvider.notifier)
                      .seek(Duration(milliseconds: v.round()));
                }
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatListenTime(Duration(milliseconds: at.round())),
                style: style,
              ),
              Text(formatListenTime(d), style: style),
            ],
          ),
        ),
      ],
    );
  }
}

class _SleepButton extends ConsumerWidget {
  const _SleepButton({required this.state});
  final ListenState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = state;
    final at = s.sleepAt;
    final String label;
    if (s.sleep == ListenSleep.endOfCard) {
      label = 'End of card';
    } else if (at != null) {
      final left = at.difference(DateTime.now());
      final mins = (left.inSeconds / 60).ceil().clamp(1, 999);
      label = '$mins min';
    } else {
      label = 'Sleep timer';
    }
    return PopupMenuButton<ListenSleep>(
      key: const ValueKey('listen-sleep'),
      tooltip: 'Sleep timer',
      initialValue: s.sleep,
      onSelected: ref.read(listenProvider.notifier).setSleep,
      itemBuilder: (_) => [
        for (final o in ListenSleep.values)
          PopupMenuItem(value: o, child: Text(o.label)),
      ],
      child: IgnorePointer(
        child: OutlinedButton.icon(
          onPressed: () {},
          icon: Icon(
            s.sleep == ListenSleep.off ? Icons.bedtime_outlined : Icons.bedtime,
          ),
          label: Text(label),
        ),
      ),
    );
  }
}
