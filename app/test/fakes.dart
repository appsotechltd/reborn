import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reborn/src/api/api_client.dart';
import 'package:reborn/src/api/models.dart';
import 'package:reborn/src/data/offline_cache.dart';
import 'package:reborn/src/data/repository.dart';
import 'package:reborn/src/data/speaker.dart';
import 'package:reborn/src/features/listen/listen_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSpeaker extends Speaker {
  final spoken = <String>[];
  String? _id;

  @override
  String? get speakingId => _id;

  @override
  Future<void> speak(String id, String text) async {
    spoken.add(text);
    _id = id;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _id = null;
    notifyListeners();
  }

  /// The device voice reached the end of the text.
  void finish() {
    _id = null;
    notifyListeners();
  }
}

/// Repository whose network calls are stubbed; anything not overridden
/// fails like an unreachable server.
class FakeRepository extends RebornRepository {
  FakeRepository(SharedPreferences prefs)
    : super(
        ApiClient(
          httpClient: MockClient(
            (_) async => throw http.ClientException('offline'),
          ),
        ),
        OfflineCache(prefs),
      );

  ReviewDue due = const ReviewDue(items: [], dueCount: 0);
  final graded = <(String, Grade)>[];

  @override
  Future<Fetched<List<Topic>>> topics() async => const Fetched(kDefaultTopics);

  @override
  Future<ReviewDue> reviewDue({int limit = 20}) async => due;

  @override
  Future<ReviewResult> review(String cardId, Grade grade) async {
    graded.add((cardId, grade));
    return const ReviewResult(intervalDays: 1, reps: 1);
  }
}

/// Plays nothing: records what Listen mode asked for, and lets the test
/// move the position and end recordings.
class FakeListenAudio implements ListenAudio {
  final played = <String>[];
  final prefetched = <String>[];
  final seeks = <Duration>[];
  final failing = <String>{};
  int chimes = 0;
  bool playing = false;
  double speed = 1;
  Duration? length = const Duration(seconds: 40);
  Duration _position = Duration.zero;

  final _positions = StreamController<Duration>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final _interruptions = StreamController<bool>.broadcast();

  void moveTo(Duration p) {
    _position = p;
    _positions.add(p);
  }

  void finish() => _completed.add(null);

  void interrupt({required bool resume}) => _interruptions.add(resume);

  @override
  Future<Duration?> play(String url, {double speed = 1}) async {
    if (failing.contains(url)) throw Exception('unreachable');
    played.add(url);
    _position = Duration.zero;
    playing = true;
    this.speed = speed;
    return length;
  }

  @override
  Future<void> pause() async => playing = false;

  @override
  Future<void> resume() async => playing = true;

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    _position = position;
  }

  @override
  Future<void> setSpeed(double speed) async => this.speed = speed;

  @override
  Future<void> stop() async => playing = false;

  @override
  Duration get position => _position;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<void> get completed => _completed.stream;

  @override
  Stream<bool> get interruptions => _interruptions.stream;

  @override
  Future<void> playChime() async => chimes++;

  @override
  Future<void> prefetch(List<String> urls) async => prefetched.addAll(urls);

  @override
  Future<void> dispose() async {}
}
