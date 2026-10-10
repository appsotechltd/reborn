import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Base URL of the Reborn API, from `--dart-define=API_BASE_URL=...`.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8080',
);

/// An error returned by the API (`{"error":{"code","message"}}`) or a
/// transport failure ([isNetwork] true, [statusCode] 0).
class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  const ApiException.network([this.message = 'Could not reach Reborn'])
    : statusCode = 0,
      code = 'network_error';

  final int statusCode;
  final String code;
  final String message;

  bool get isNetwork => statusCode == 0;
  bool get isUnauthorized => statusCode == 401;
  bool get isRateLimited => statusCode == 429;
  bool get isAgentUnavailable =>
      code == 'agent_unavailable' || statusCode == 503;

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}

typedef TokenGetter = String? Function();

class ApiClient {
  ApiClient({
    http.Client? httpClient,
    String baseUrl = apiBaseUrl,
    TokenGetter? token,
    this.timeout = const Duration(seconds: 20),
  }) : _http = httpClient ?? http.Client(),
       _base = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _token = token ?? (() => null);

  final http.Client _http;
  final String _base;
  final TokenGetter _token;
  final Duration timeout;

  Uri _uri(String path, [Map<String, String?>? query]) {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null && v.isNotEmpty) q[k] = v;
    });
    return Uri.parse('$_base$path')
        .replace(queryParameters: q.isEmpty ? null : q);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String?>? query,
    Object? body,
  }) async {
    final req = http.Request(method, _uri(path, query));
    req.headers['Accept'] = 'application/json';
    final token = _token();
    if (token != null && token.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $token';
    }
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    http.Response res;
    try {
      res = await http.Response.fromStream(
        await _http.send(req).timeout(timeout),
      );
    } on TimeoutException {
      throw const ApiException.network('The request timed out');
    } on http.ClientException catch (e) {
      throw ApiException.network(e.message);
    } catch (e) {
      // SocketException on mobile, browser XHR errors on web.
      throw const ApiException.network();
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.statusCode == 204 || res.bodyBytes.isEmpty) return null;
      try {
        return jsonDecode(utf8.decode(res.bodyBytes));
      } on FormatException {
        throw ApiException(
          statusCode: res.statusCode,
          code: 'bad_response',
          message: 'The server sent an unreadable response',
        );
      }
    }
    throw _parseError(res);
  }

  static ApiException _parseError(http.Response res) {
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map && decoded['error'] is Map) {
        final err = decoded['error'] as Map;
        return ApiException(
          statusCode: res.statusCode,
          code: err['code']?.toString() ?? 'http_${res.statusCode}',
          message: err['message']?.toString() ?? 'Request failed',
        );
      }
    } catch (_) {
      // fall through
    }
    return ApiException(
      statusCode: res.statusCode,
      code: 'http_${res.statusCode}',
      message: 'Request failed (${res.statusCode})',
    );
  }

  Map<String, dynamic> _map(dynamic v) =>
      v is Map<String, dynamic> ? v : <String, dynamic>{};

  // ---- Public ----

  Future<List<Topic>> topics() async {
    final json = _map(await _send('GET', '/v1/topics'));
    return (json['topics'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Topic.fromJson)
        .toList();
  }

  Future<FeedPage> feed({
    List<String>? topics,
    String? cursor,
    int limit = 20,
  }) async => FeedPage.fromJson(
    _map(
      await _send(
        'GET',
        '/v1/feed',
        query: {
          'topics': (topics == null || topics.isEmpty)
              ? null
              : topics.join(','),
          'cursor': cursor,
          'limit': '$limit',
        },
      ),
    ),
  );

  Future<DailyIdea> daily() async =>
      DailyIdea.fromJson(_map(await _send('GET', '/v1/daily')));

  Future<IdeaCard> card(String id) async => IdeaCard.fromJson(
    _map(await _send('GET', '/v1/cards/${Uri.encodeComponent(id)}')),
  );

  Future<List<IdeaCard>> cards(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final json = _map(
      await _send('GET', '/v1/cards', query: {'ids': ids.join(',')}),
    );
    return parseCards(json['cards']);
  }

  Future<void> recordView(String id) =>
      _send('POST', '/v1/cards/${Uri.encodeComponent(id)}/view');

  Future<SourceDetail> source(String id) async => SourceDetail.fromJson(
    _map(await _send('GET', '/v1/sources/${Uri.encodeComponent(id)}')),
  );

  Future<List<IdeaCard>> search(
    String q, {
    String? topic,
    int limit = 20,
  }) async {
    final json = _map(
      await _send(
        'GET',
        '/v1/search',
        query: {'q': q, 'topic': topic, 'limit': '$limit'},
      ),
    );
    return parseCards(json['cards']);
  }

  // ---- Auth ----

  Future<AuthResult> register(
    String email,
    String password,
    String displayName,
  ) async => AuthResult.fromJson(
    _map(
      await _send(
        'POST',
        '/v1/auth/register',
        body: {
          'email': email,
          'password': password,
          'display_name': displayName,
        },
      ),
    ),
  );

  Future<AuthResult> login(String email, String password) async =>
      AuthResult.fromJson(
        _map(
          await _send(
            'POST',
            '/v1/auth/login',
            body: {'email': email, 'password': password},
          ),
        ),
      );

  Future<User> me() async => User.fromJson(_map(await _send('GET', '/v1/me')));

  Future<User> updateMe({String? displayName, List<String>? topics}) async =>
      User.fromJson(
        _map(
          await _send(
            'PATCH',
            '/v1/me',
            body: {'display_name': ?displayName, 'topics': ?topics},
          ),
        ),
      );

  // ---- Stashes ----

  Future<List<Stash>> stashes() async {
    final json = _map(await _send('GET', '/v1/stashes'));
    return (json['stashes'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Stash.fromJson)
        .toList();
  }

  Future<Stash> createStash(String name, {String? description}) async =>
      Stash.fromJson(
        _map(
          await _send(
            'POST',
            '/v1/stashes',
            body: {'name': name, 'description': ?description},
          ),
        ),
      );

  Future<StashDetail> stash(String id) async =>
      StashDetail.fromJson(_map(await _send('GET', '/v1/stashes/$id')));

  Future<Stash> updateStash(
    String id, {
    String? name,
    String? description,
  }) async => Stash.fromJson(
    _map(
      await _send(
        'PATCH',
        '/v1/stashes/$id',
        body: {'name': ?name, 'description': ?description},
      ),
    ),
  );

  Future<void> deleteStash(String id) => _send('DELETE', '/v1/stashes/$id');

  Future<void> addToStash(String stashId, String cardId) =>
      _send('PUT', '/v1/stashes/$stashId/cards/${Uri.encodeComponent(cardId)}');

  Future<void> removeFromStash(String stashId, String cardId) => _send(
    'DELETE',
    '/v1/stashes/$stashId/cards/${Uri.encodeComponent(cardId)}',
  );

  // ---- Review & quiz ----

  Future<ReviewDue> reviewDue({int limit = 20}) async => ReviewDue.fromJson(
    _map(await _send('GET', '/v1/review/due', query: {'limit': '$limit'})),
  );

  Future<ReviewResult> review(String cardId, Grade grade) async =>
      ReviewResult.fromJson(
        _map(
          await _send(
            'POST',
            '/v1/review/${Uri.encodeComponent(cardId)}',
            body: {'grade': grade.name},
          ),
        ),
      );

  Future<List<IdeaCard>> quiz({String? topic, int limit = 5}) async {
    final json = _map(
      await _send(
        'GET',
        '/v1/quiz',
        query: {'topic': topic, 'limit': '$limit'},
      ),
    );
    return parseCards(json['cards']);
  }

  // ---- Contributions & moderation ----

  Future<Contribution> contribute(ContributionDraft draft) async =>
      Contribution.fromJson(
        _map(await _send('POST', '/v1/contributions', body: draft.toJson())),
      );

  Future<List<Contribution>> myContributions() async =>
      _contributions(await _send('GET', '/v1/contributions/mine'));

  Future<List<Contribution>> moderationQueue() async =>
      _contributions(await _send('GET', '/v1/moderation/queue'));

  Future<Contribution> approve(String id, {String? note}) async =>
      Contribution.fromJson(
        _map(
          await _send(
            'POST',
            '/v1/moderation/$id/approve',
            body: {if (note != null && note.isNotEmpty) 'note': note},
          ),
        ),
      );

  Future<Contribution> reject(String id, String note) async =>
      Contribution.fromJson(
        _map(
          await _send(
            'POST',
            '/v1/moderation/$id/reject',
            body: {'note': note},
          ),
        ),
      );

  List<Contribution> _contributions(dynamic v) =>
      (_map(v)['contributions'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Contribution.fromJson)
          .toList();

  // ---- Agent ----

  Future<ChatReply> chat(List<ChatMessage> messages) async =>
      ChatReply.fromJson(
        _map(
          await _send(
            'POST',
            '/v1/agent/chat',
            body: {'messages': messages.map((m) => m.toJson()).toList()},
          ),
        ),
      );
}
