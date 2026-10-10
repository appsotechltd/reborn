import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reborn/src/api/api_client.dart';
import 'package:reborn/src/api/models.dart';
import 'package:reborn/src/data/offline_cache.dart';
import 'package:reborn/src/data/repository.dart';
import 'package:reborn/src/data/speaker.dart';
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
