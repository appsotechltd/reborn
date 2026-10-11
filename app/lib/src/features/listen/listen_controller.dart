import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/models.dart';
import '../../data/providers.dart';
import '../../data/speaker.dart';
import 'listen_audio.dart';

/// The speeds Listen mode offers.
const kListenSpeeds = [0.8, 1.0, 1.25, 1.5];

/// Fetch the next timeline page when this many posts or fewer are left.
const kListenPreloadRemaining = 3;

/// How many upcoming recordings to download ahead.
const kListenPrefetch = 3;

/// A card heard this far (or to its end) counts as seen and read.
const kListenReadFraction = 0.7;

/// Skipping a card within this much marks nothing; later, it counts as seen.
const kListenSeenAfter = Duration(seconds: 5);

/// "Previous" restarts the card after this much, else goes back a card.
const kListenRestartAfter = Duration(seconds: 3);

/// Device-voice reading pace, for its progress bar (words per second at 1x).
const kListenWordsPerSecond = 2.6;

enum ListenSleep {
  off(null, 'Off'),
  min15(Duration(minutes: 15), '15 minutes'),
  min30(Duration(minutes: 30), '30 minutes'),
  min60(Duration(minutes: 60), '60 minutes'),
  endOfCard(null, 'End of this card');

  const ListenSleep(this.after, this.label);
  final Duration? after;
  final String label;
}

class ListenState {
  const ListenState({
    this.queue = const [],
    this.index = 0,
    this.playing = false,
    this.loading = false,
    this.position = Duration.zero,
    this.duration,
    this.speed = 1,
    this.deviceVoice = false,
    this.sleep = ListenSleep.off,
    this.sleepAt,
    this.finished = false,
    this.single = false,
  });

  /// The posts to play, in timeline order.
  final List<Post> queue;
  final int index;

  /// Playing, or about to (between cards); false when paused.
  final bool playing;

  /// Loading the current card's recording.
  final bool loading;
  final Duration position;
  final Duration? duration;
  final double speed;

  /// The current card has no recording and is read by the device voice.
  final bool deviceVoice;
  final ListenSleep sleep;

  /// When a timed sleep timer pauses Listen mode.
  final DateTime? sleepAt;

  /// Played to the end of the queue.
  final bool finished;

  /// One card from its page (no queue).
  final bool single;

  /// A Listen session is open (the mini-player shows).
  bool get active => queue.isNotEmpty;

  Post? get current => index < queue.length ? queue[index] : null;

  bool get hasNext => index + 1 < queue.length;

  ListenState copyWith({
    List<Post>? queue,
    int? index,
    bool? playing,
    bool? loading,
    Duration? position,
    Duration? duration,
    bool clearDuration = false,
    double? speed,
    bool? deviceVoice,
    ListenSleep? sleep,
    DateTime? sleepAt,
    bool clearSleepAt = false,
    bool? finished,
    bool? single,
  }) => ListenState(
    queue: queue ?? this.queue,
    index: index ?? this.index,
    playing: playing ?? this.playing,
    loading: loading ?? this.loading,
    position: position ?? this.position,
    duration: clearDuration ? null : (duration ?? this.duration),
    speed: speed ?? this.speed,
    deviceVoice: deviceVoice ?? this.deviceVoice,
    sleep: sleep ?? this.sleep,
    sleepAt: clearSleepAt ? null : (sleepAt ?? this.sleepAt),
    finished: finished ?? this.finished,
    single: single ?? this.single,
  );
}

enum _Output { none, audio, voice }

/// Listen mode: plays timeline posts one after another, each card's
/// recording or, without one, the device voice; a chime between cards; the
/// next page loads as the queue runs low. Marks cards seen and read by how
/// much was heard (see [kListenReadFraction] and [kListenSeenAfter]).
class ListenController extends Notifier<ListenState> {
  static const speedKey = 'listen.speed';

  /// Bumped on every change of card or stop, so a stale async step (a
  /// recording that finished loading after a skip) does nothing.
  int _gen = 0;
  _Output _output = _Output.none;

  /// Whether the current card's output has started (a card cued while
  /// paused starts on play).
  bool _started = false;

  List<String>? _topics;
  String? _cursor;
  Future<void>? _pageLoad;

  Duration _heard = Duration.zero;
  final _seen = <String>{};
  final _read = <String>{};

  // Device voice.
  String? _voiceId;
  bool _voiceStarted = false;
  Timer? _voiceTicker;
  Speaker? _speaker;

  // Audio.
  ListenAudio? _audio;
  final _subs = <StreamSubscription<Object?>>[];
  bool _interrupted = false;

  Timer? _sleepTimer;

  ListenMediaSession get _session => ref.read(listenMediaSessionProvider);

  @override
  ListenState build() {
    ref.onDispose(_dispose);
    double? saved;
    try {
      saved = ref.read(sharedPreferencesProvider).getDouble(speedKey);
    } catch (_) {
      // No saved speed.
    }
    final session = ref.read(listenMediaSessionProvider);
    session.bind(
      ListenMediaControls(
        play: play,
        pause: pause,
        next: next,
        previous: previous,
        seek: seek,
        stop: stop,
      ),
    );
    return ListenState(speed: kListenSpeeds.contains(saved) ? saved! : 1.0);
  }

  void _dispose() {
    _gen++;
    _voiceTicker?.cancel();
    _sleepTimer?.cancel();
    _speaker?.removeListener(_onSpeaker);
    for (final s in _subs) {
      s.cancel();
    }
  }

  // ---- Starting ----

  /// Starts Listen mode on the timeline's [posts] from [index], loading
  /// further pages from [cursor] with the same [topics] filter.
  Future<void> startTimeline({
    required List<Post> posts,
    int index = 0,
    String? cursor,
    List<String>? topics,
  }) async {
    if (posts.isEmpty) return;
    _leave();
    await _stopOutput();
    _topics = topics;
    _cursor = cursor;
    _pageLoad = null;
    _set(
      ListenState(
        queue: List.of(posts),
        index: index.clamp(0, posts.length - 1),
        playing: true,
        speed: state.speed,
      ),
    );
    await _cue(state.index);
  }

  /// Plays one card (its page's Listen button): its recording, or else the
  /// device voice. No queue follows it.
  Future<void> playCard(IdeaCard card) async {
    _leave();
    await _stopOutput();
    _topics = null;
    _cursor = null;
    _pageLoad = null;
    _set(
      ListenState(
        queue: [Post.fromCard(card)],
        playing: true,
        speed: state.speed,
        single: true,
      ),
    );
    await _cue(0);
  }

  // ---- Controls ----

  Future<void> play() async {
    final s = state;
    if (!s.active || s.playing) return;
    _interrupted = false;
    if (s.finished) {
      _set(s.copyWith(playing: true, finished: false));
      await _cue(s.index);
      return;
    }
    _set(s.copyWith(playing: true));
    if (!_started) {
      await _start(_gen);
    } else if (_output == _Output.audio) {
      await _audio?.resume();
    } else if (_output == _Output.voice) {
      // The device voice can't pause mid-sentence: it starts the card again.
      await _start(_gen);
    }
  }

  Future<void> pause() async {
    final s = state;
    if (!s.active || !s.playing) return;
    _set(s.copyWith(playing: false));
    if (_output == _Output.audio) {
      await _audio?.pause();
    } else if (_output == _Output.voice) {
      await _stopVoice();
      _started = false;
    }
  }

  Future<void> toggle() => state.playing ? pause() : play();

  Future<void> next() async {
    final s = state;
    if (!s.active) return;
    if (!s.hasNext) await _loadMore();
    if (!state.hasNext) return;
    _leave();
    await _go(state.index + 1);
  }

  /// Restarts the card when more than [kListenRestartAfter] in, else goes
  /// back a card (or restarts the first).
  Future<void> previous() async {
    final s = state;
    if (!s.active) return;
    if (s.position > kListenRestartAfter || s.index == 0) {
      await seek(Duration.zero);
      return;
    }
    _leave();
    await _go(s.index - 1);
  }

  Future<void> seek(Duration position) async {
    final s = state;
    if (!s.active) return;
    if (position < Duration.zero) position = Duration.zero;
    final d = s.duration;
    if (d != null && position > d) position = d;
    if (_output == _Output.audio) {
      _set(s.copyWith(position: position), session: true);
      await _audio?.seek(position);
    } else if (position == Duration.zero && s.playing) {
      // The device voice can only start over.
      await _start(_gen);
    }
  }

  Future<void> back10() => seek(state.position - const Duration(seconds: 10));

  Future<void> setSpeed(double speed) async {
    _set(state.copyWith(speed: speed), session: true);
    try {
      await ref.read(sharedPreferencesProvider).setDouble(speedKey, speed);
    } catch (_) {
      // Remembered for this session only.
    }
    _speakerOrNull?.setRate(speed);
    if (_output == _Output.audio) await _audio?.setSpeed(speed);
  }

  /// The next speed in [kListenSpeeds], wrapping round.
  Future<void> cycleSpeed() {
    final i = kListenSpeeds.indexOf(state.speed);
    return setSpeed(kListenSpeeds[(i + 1) % kListenSpeeds.length]);
  }

  void setSleep(ListenSleep sleep) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    final after = sleep.after;
    if (after != null) {
      _sleepTimer = Timer(after, () {
        _sleepTimer = null;
        _set(state.copyWith(sleep: ListenSleep.off, clearSleepAt: true));
        pause();
      });
    }
    _set(
      state.copyWith(
        sleep: sleep,
        sleepAt: after == null ? null : DateTime.now().add(after),
        clearSleepAt: after == null,
      ),
    );
  }

  /// Ends Listen mode.
  Future<void> stop() async {
    if (!state.active) return;
    _leave();
    _sleepTimer?.cancel();
    _sleepTimer = null;
    await _stopOutput();
    _session.clear();
    state = ListenState(speed: state.speed);
  }

  // ---- Queue ----

  Future<void> _go(int index) async {
    await _stopOutput();
    await _cue(index);
  }

  /// Makes [index] the current card and, when playing, starts it (after
  /// the chime when [chime]).
  Future<void> _cue(int index, {bool chime = false}) async {
    final gen = ++_gen;
    _started = false;
    _heard = Duration.zero;
    final post = state.queue[index];
    final card = post.card;
    final audio = card.audio;
    _set(
      state.copyWith(
        index: index,
        position: Duration.zero,
        duration: audio != null && audio.durationS > 0
            ? audio.duration
            : _voiceDuration(card),
        deviceVoice: audio == null,
        finished: false,
        loading: false,
      ),
      session: true,
    );
    _session.setItem(
      id: post.id,
      title: card.title,
      subtitle: subtitleOf(card),
      duration: state.duration,
    );
    _prefetch();
    unawaited(_maybeLoadMore());
    if (!state.playing) return;
    if (chime) {
      _set(state.copyWith(loading: true));
      await _audioOrNull()?.playChime();
      if (gen != _gen) return;
      if (!state.playing) {
        _set(state.copyWith(loading: false));
        return;
      }
    }
    await _start(gen);
  }

  /// Starts the current card's output from the beginning.
  Future<void> _start(int gen) async {
    final post = state.current;
    if (post == null) return;
    await _stopOutput();
    if (gen != _gen) return;
    _started = true;
    final audio = post.card.audio;
    if (audio != null) {
      final player = _audioOrNull();
      if (player != null) {
        _set(state.copyWith(loading: true, position: Duration.zero));
        try {
          _output = _Output.audio;
          final d = await player.play(
            resolveMediaUrl(audio.url),
            speed: state.speed,
          );
          if (gen != _gen) return;
          _set(
            state.copyWith(
              loading: false,
              duration: d ?? state.duration,
              deviceVoice: false,
            ),
            session: true,
          );
          if (!state.playing) await player.pause();
          return;
        } catch (_) {
          if (gen != _gen) return;
          _output = _Output.none;
          // Couldn't load the recording: the device voice reads it instead.
        }
      }
    }
    _set(
      state.copyWith(
        loading: false,
        deviceVoice: true,
        position: Duration.zero,
        duration: _voiceDuration(post.card),
      ),
      session: true,
    );
    await _startVoice(post);
  }

  /// The card finished playing.
  Future<void> _complete(int gen) async {
    if (gen != _gen) return;
    _markRead();
    _output = _Output.none;
    _started = false;
    if (state.sleep == ListenSleep.endOfCard) {
      _set(state.copyWith(sleep: ListenSleep.off, playing: false));
      if (state.hasNext) await _cue(state.index + 1);
      return;
    }
    if (!state.hasNext) await _loadMore();
    if (gen != _gen) return;
    if (!state.hasNext) {
      _set(state.copyWith(playing: false, finished: true), session: true);
      return;
    }
    await _cue(state.index + 1, chime: true);
  }

  /// Loads the next page when [kListenPreloadRemaining] posts or fewer are
  /// left.
  Future<void> _maybeLoadMore() async {
    final s = state;
    if (s.queue.length - 1 - s.index > kListenPreloadRemaining) return;
    await _loadMore();
  }

  Future<void> _loadMore() {
    if (state.single || _cursor == null) return Future.value();
    return _pageLoad ??= () async {
      try {
        final page = await ref
            .read(repositoryProvider)
            .timeline(topics: _topics, cursor: _cursor);
        if (!state.active) return;
        final have = state.queue.map((p) => p.id).toSet();
        _cursor = page.value.nextCursor;
        _set(
          state.copyWith(
            queue: [
              ...state.queue,
              ...page.value.posts.where((p) => !have.contains(p.id)),
            ],
          ),
        );
      } catch (_) {
        // Tried again as the queue moves on.
      } finally {
        _pageLoad = null;
      }
    }();
  }

  void _prefetch() {
    final s = state;
    final urls = [
      for (final p in s.queue.skip(s.index + 1).take(kListenPrefetch))
        if (p.card.audio != null) resolveMediaUrl(p.card.audio!.url),
    ];
    if (urls.isEmpty) return;
    unawaited(_audioOrNull()?.prefetch(urls));
  }

  // ---- Seen and read ----

  /// Leaving the current card early: seen if heard past
  /// [kListenSeenAfter], read too if past [kListenReadFraction].
  void _leave() {
    final post = state.current;
    if (post == null) return;
    final d = state.duration;
    if (d != null &&
        d > Duration.zero &&
        _heard.inMilliseconds >= d.inMilliseconds * kListenReadFraction) {
      _markRead();
    } else if (_heard >= kListenSeenAfter) {
      _markSeen(post);
    }
  }

  void _heardUpTo(Duration position) {
    if (position > _heard) _heard = position;
    final d = state.duration;
    if (d != null &&
        d > Duration.zero &&
        _heard.inMilliseconds >= d.inMilliseconds * kListenReadFraction) {
      _markRead();
    }
  }

  bool get _signedIn => ref.read(sessionProvider).signedIn;

  void _markSeen(Post post) {
    if (!_signedIn || !_seen.add(post.id)) return;
    unawaited(ref.read(repositoryProvider).markSeen([post.id]));
  }

  void _markRead() {
    final post = state.current;
    if (post == null) return;
    _markSeen(post);
    if (!_signedIn || !_read.add(post.card.id)) return;
    unawaited(ref.read(repositoryProvider).recordView(post.card.id));
  }

  // ---- Outputs ----

  Future<void> _stopOutput() async {
    final was = _output;
    _output = _Output.none;
    if (was == _Output.audio) {
      await _audio?.stop();
    } else if (was == _Output.voice) {
      await _stopVoice();
    }
  }

  ListenAudio? _audioOrNull() {
    if (_audio != null) return _audio;
    try {
      final audio = ref.read(listenAudioProvider);
      _audio = audio;
      _subs
        ..add(audio.positionStream.listen(_onPosition))
        ..add(audio.completed.listen((_) => _onAudioComplete()))
        ..add(audio.interruptions.listen(_onInterruption));
      return audio;
    } catch (_) {
      return null;
    }
  }

  void _onPosition(Duration p) {
    if (_output != _Output.audio || state.loading) return;
    _heardUpTo(p);
    _set(state.copyWith(position: p));
  }

  void _onAudioComplete() {
    if (_output != _Output.audio) return;
    final d = state.duration;
    if (d != null) _heardUpTo(d);
    _complete(_gen);
  }

  void _onInterruption(bool resume) {
    if (!resume) {
      if (state.playing) {
        _interrupted = true;
        pause();
      }
    } else if (_interrupted) {
      _interrupted = false;
      play();
    }
  }

  Speaker? get _speakerOrNull => _speaker;

  Duration _voiceDuration(IdeaCard card) {
    final words = card.spokenText.split(RegExp(r'\s+')).length;
    return Duration(
      milliseconds: (words / (kListenWordsPerSecond * state.speed) * 1000)
          .round(),
    );
  }

  Future<void> _startVoice(Post post) async {
    final Speaker speaker = _speaker ?? ref.read(speakerProvider);
    if (_speaker == null) {
      _speaker = speaker;
      speaker.addListener(_onSpeaker);
    }
    _output = _Output.voice;
    _voiceId = post.card.id;
    _voiceStarted = false;
    var elapsed = Duration.zero;
    const tick = Duration(milliseconds: 250);
    _voiceTicker?.cancel();
    _voiceTicker = Timer.periodic(tick, (_) {
      elapsed += tick;
      final d = state.duration ?? elapsed;
      final p = elapsed > d ? d : elapsed;
      _heardUpTo(p);
      _set(state.copyWith(position: p));
    });
    await speaker.setRate(state.speed);
    await speaker.speak(post.card.id, post.card.spokenText);
  }

  Future<void> _stopVoice() async {
    _voiceTicker?.cancel();
    _voiceTicker = null;
    final id = _voiceId;
    _voiceId = null;
    if (id != null && _speaker?.speakingId == id) await _speaker!.stop();
  }

  void _onSpeaker() {
    final id = _voiceId;
    if (_output != _Output.voice || id == null) return;
    final speaking = _speaker?.speakingId;
    if (speaking == id) {
      _voiceStarted = true;
      return;
    }
    if (!_voiceStarted) return;
    // Finished reading. Less than a second means it couldn't speak at all:
    // skip the card without marking it.
    final heardEnough = state.position >= const Duration(seconds: 1);
    _voiceTicker?.cancel();
    _voiceTicker = null;
    _voiceId = null;
    final gen = _gen;
    if (heardEnough) {
      final d = state.duration;
      if (d != null) _heardUpTo(d);
      _complete(gen);
    } else {
      _output = _Output.none;
      _started = false;
      _skipUnplayable(gen);
    }
  }

  Future<void> _skipUnplayable(int gen) async {
    if (gen != _gen) return;
    if (!state.hasNext) await _loadMore();
    if (gen != _gen) return;
    if (!state.hasNext) {
      _set(state.copyWith(playing: false, finished: true), session: true);
      return;
    }
    await _cue(state.index + 1);
  }

  // ---- State ----

  /// Sets [s]; with [session] (or when play state changes) the lock screen
  /// follows.
  void _set(ListenState s, {bool session = false}) {
    final old = state;
    state = s;
    if (!s.active) return;
    if (session ||
        old.playing != s.playing ||
        old.loading != s.loading ||
        old.index != s.index) {
      _session.setPlayback(
        playing: s.playing,
        loading: s.loading,
        position: s.position,
        speed: s.speed,
      );
    }
  }
}

/// "Source title · Author" for a card.
String subtitleOf(IdeaCard card) {
  final authors = card.source.authors.join(', ');
  return [card.source.title, authors].where((s) => s.isNotEmpty).join(' · ');
}

final listenProvider = NotifierProvider<ListenController, ListenState>(
  ListenController.new,
);
