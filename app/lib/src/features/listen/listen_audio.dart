import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'just_audio_player.dart';

/// Plays Listen mode's recordings. The real one wraps just_audio
/// ([JustAudioListenAudio]); tests use a fake, so nothing here needs a
/// platform channel.
abstract class ListenAudio {
  /// Loads [url] and starts playing it from the start at [speed]. Returns the
  /// recording's length when known. Throws when it can't be loaded.
  Future<Duration?> play(String url, {double speed = 1});

  Future<void> pause();
  Future<void> resume();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);

  /// Stops and unloads the current recording.
  Future<void> stop();

  /// Where the current recording is.
  Duration get position;

  /// Position updates while playing.
  Stream<Duration> get positionStream;

  /// Fires when the current recording plays to its end.
  Stream<void> get completed;

  /// Outside interruptions: false to pause now (a call, headphones
  /// unplugged), true when playing may resume (the call ended).
  Stream<bool> get interruptions;

  /// Plays the short chime between cards; completes when it has finished
  /// (or failed: a missing chime never stops the stream).
  Future<void> playChime();

  /// Starts (true) or pauses (false) the background music, a quiet looping
  /// track under the voice. Best effort: failing to play it changes nothing
  /// else.
  Future<void> setMusic(bool playing);

  /// Downloads [urls] ahead of time so a short loss of signal doesn't stop
  /// playback. Best effort; a no-op where caching isn't supported (web).
  Future<void> prefetch(List<String> urls);

  Future<void> dispose();
}

/// The lock screen, notification and headphone controls. The real one is
/// audio_service ([AudioServiceListenSession], set up in `main()`); without
/// it (tests, or if it fails to start) nothing shows outside the app.
abstract class ListenMediaSession {
  /// Wires the session's buttons to Listen mode.
  void bind(ListenMediaControls controls);

  /// What's playing: the card title, "Source title · Author", and its length.
  void setItem({
    required String id,
    required String title,
    required String subtitle,
    Duration? duration,
  });

  void setPlayback({
    required bool playing,
    required bool loading,
    required Duration position,
    required double speed,
  });

  /// Listen mode ended: clears the notification.
  void clear();
}

/// What the lock screen and headphones can ask Listen mode to do.
class ListenMediaControls {
  const ListenMediaControls({
    required this.play,
    required this.pause,
    required this.next,
    required this.previous,
    required this.seek,
    required this.stop,
  });

  final Future<void> Function() play;
  final Future<void> Function() pause;
  final Future<void> Function() next;
  final Future<void> Function() previous;
  final Future<void> Function(Duration position) seek;
  final Future<void> Function() stop;
}

class NoListenMediaSession implements ListenMediaSession {
  const NoListenMediaSession();

  @override
  void bind(ListenMediaControls controls) {}

  @override
  void setItem({
    required String id,
    required String title,
    required String subtitle,
    Duration? duration,
  }) {}

  @override
  void setPlayback({
    required bool playing,
    required bool loading,
    required Duration position,
    required double speed,
  }) {}

  @override
  void clear() {}
}

/// Made on first use, so screens that never play a recording (and tests)
/// never touch the audio plugins.
final listenAudioProvider = Provider<ListenAudio>((ref) {
  final audio = JustAudioListenAudio();
  ref.onDispose(audio.dispose);
  return audio;
});

/// Overridden in `main()` once audio_service has started.
final listenMediaSessionProvider = Provider<ListenMediaSession>(
  (ref) => const NoListenMediaSession(),
);
