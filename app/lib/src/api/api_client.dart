import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_models.dart';
import 'models.dart';

/// Base URL of the Reborn API, from `--dart-define=API_BASE_URL=...`.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8080',
);

/// Resolves a media URL from the API (explainer videos and posters): absolute
/// URLs are kept, paths are resolved against [base].
String resolveMediaUrl(String url, [String base = apiBaseUrl]) {
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  return '$b${url.startsWith('/') ? '' : '/'}$url';
}

/// Base URL of the Reborn website, from `--dart-define=WEB_BASE_URL=...`.
/// Shared links and password reset pages live here.
const String webBaseUrl = String.fromEnvironment(
  'WEB_BASE_URL',
  defaultValue: 'https://reborn.app',
);

/// The canonical web link of a post (an idea card).
String postWebLink(String postId, {String base = webBaseUrl}) {
  final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  return '$b/ideas/${Uri.encodeComponent(postId)}';
}

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
    Duration? timeout,
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
        await _http.send(req).timeout(timeout ?? this.timeout),
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

  /// The library's books (GET /v1/sources), ordered by title. [q] matches
  /// the title or an author's name.
  Future<SourceListPage> sources({
    String? topic,
    String? q,
    String? cursor,
    int limit = 50,
  }) async => SourceListPage.fromJson(
    _map(
      await _send(
        'GET',
        '/v1/sources',
        query: {'topic': topic, 'q': q, 'cursor': cursor, 'limit': '$limit'},
      ),
    ),
  );

  /// Everyone with published cards (GET /v1/authors), ordered by name.
  Future<AuthorListPage> authors({
    String? topic,
    String? q,
    String? cursor,
    int limit = 50,
  }) async => AuthorListPage.fromJson(
    _map(
      await _send(
        'GET',
        '/v1/authors',
        query: {'topic': topic, 'q': q, 'cursor': cursor, 'limit': '$limit'},
      ),
    ),
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
    String displayName, {
    String? timezone,
    String? referralCode,
  }) async => AuthResult.fromJson(
    _map(
      await _send(
        'POST',
        '/v1/auth/register',
        body: {
          'email': email,
          'password': password,
          'display_name': displayName,
          if (timezone != null && timezone.isNotEmpty) 'timezone': timezone,
          if (referralCode != null && referralCode.isNotEmpty)
            'referral_code': referralCode,
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

  Future<User> updateMe({
    String? displayName,
    String? handle,
    String? bio,
    List<String>? topics,
    String? timezone,
    int? dailyGoal,
    Map<String, bool>? notify,
  }) async => User.fromJson(
    _map(
      await _send(
        'PATCH',
        '/v1/me',
        body: {
          'display_name': ?displayName,
          'handle': ?handle,
          'bio': ?bio,
          'topics': ?topics,
          'timezone': ?timezone,
          'daily_goal': ?dailyGoal,
          'notify': ?notify,
        },
      ),
    ),
  );

  Future<void> deleteMe() => _send('DELETE', '/v1/me');

  /// Always succeeds (202) whether or not the account exists.
  Future<void> forgotPassword(String email) =>
      _send('POST', '/v1/auth/forgot', body: {'email': email});

  // ---- Social ----

  String _post(String id) => '/v1/posts/${Uri.encodeComponent(id)}';

  /// With [withSummaries] the page also carries summary posts (see
  /// [Post.summary]) woven between the card posts.
  Future<PostPage> timeline({
    List<String>? topics,
    String? cursor,
    int limit = 20,
    bool withSummaries = false,
  }) async => PostPage.fromJson(
    _map(
      await _send(
        'GET',
        '/v1/timeline',
        query: {
          'topics': (topics == null || topics.isEmpty)
              ? null
              : topics.join(','),
          'cursor': cursor,
          'limit': '$limit',
          if (withSummaries) 'with': 'summaries',
        },
      ),
    ),
  );

  // ---- Full summary posts ----

  String _summary(String id) => '/v1/summaries/${Uri.encodeComponent(id)}';

  Future<SummaryPage> summaries({
    String? kind,
    String? topic,
    String? source,
    String? cursor,
    int limit = 50,
  }) async => SummaryPage.fromJson(
    _map(
      await _send(
        'GET',
        '/v1/summaries',
        query: {
          'kind': kind,
          'topic': topic,
          'source': source,
          'cursor': cursor,
          'limit': '$limit',
        },
      ),
    ),
  );

  Future<SummaryDetail> summary(String id) async =>
      SummaryDetail.fromJson(_map(await _send('GET', _summary(id))));

  Future<SummaryProgress> setSummaryProgress(
    String id,
    int position, {
    bool finished = false,
  }) async => SummaryProgress.fromJson(
    _map(
      await _send(
        'PUT',
        '${_summary(id)}/progress',
        body: {'position': position, 'finished': finished},
      ),
    ),
  );

  Future<void> markSeen(List<String> postIds) =>
      _send('POST', '/v1/seen', body: {'post_ids': postIds});

  Future<Post> post(String id) async =>
      Post.fromJson(_map(await _send('GET', _post(id))));

  Future<void> setFavorite(String postId, bool on) =>
      _send(on ? 'PUT' : 'DELETE', '${_post(postId)}/favorite');

  Future<void> setReaction(String postId, Reaction? kind) => kind == null
      ? _send('DELETE', '${_post(postId)}/reaction')
      : _send('PUT', '${_post(postId)}/reaction', body: {'kind': kind.name});

  Future<void> share(String postId, String channel) =>
      _send('POST', '${_post(postId)}/share', body: {'channel': channel});

  Future<CommentPage> comments(
    String postId, {
    String? cursor,
    int limit = 50,
  }) async => CommentPage.fromJson(
    _map(
      await _send(
        'GET',
        '${_post(postId)}/comments',
        query: {'cursor': cursor, 'limit': '$limit'},
      ),
    ),
  );

  Future<Comment> addComment(
    String postId,
    String body, {
    String? parentId,
  }) async => Comment.fromJson(
    _map(
      await _send(
        'POST',
        '${_post(postId)}/comments',
        body: {'body': body, 'parent_id': ?parentId},
      ),
    ),
  );

  Future<void> deleteComment(String id) => _send('DELETE', '/v1/comments/$id');

  Future<void> reportComment(String id, {String? reason}) => _send(
    'POST',
    '/v1/comments/$id/report',
    body: {if (reason != null && reason.isNotEmpty) 'reason': reason},
  );

  Future<PostPage> myFavorites({String? cursor, int limit = 20}) async =>
      PostPage.fromJson(
        _map(
          await _send(
            'GET',
            '/v1/me/favorites',
            query: {'cursor': cursor, 'limit': '$limit'},
          ),
        ),
      );

  Future<List<FollowItem>> following() async =>
      (_map(await _send('GET', '/v1/me/following'))['following'] as List? ??
              const [])
          .whereType<Map<String, dynamic>>()
          .map(FollowItem.fromJson)
          .toList();

  Future<FollowState> setFollow(
    FollowKind kind,
    String target,
    bool on,
  ) async => FollowState.fromJson(
    _map(
      await _send(
        on ? 'PUT' : 'DELETE',
        '/v1/follows/${kind.name}/${Uri.encodeComponent(target)}',
      ),
    ),
  );

  Future<Profile> profile(String handle) async => Profile.fromJson(
    _map(await _send('GET', '/v1/users/${Uri.encodeComponent(handle)}')),
  );

  Future<PostPage> userFavorites(
    String handle, {
    String? cursor,
    int limit = 20,
  }) async => PostPage.fromJson(
    _map(
      await _send(
        'GET',
        '/v1/users/${Uri.encodeComponent(handle)}/favorites',
        query: {'cursor': cursor, 'limit': '$limit'},
      ),
    ),
  );

  Future<AuthorPage> author(String name) async => AuthorPage.fromJson(
    _map(await _send('GET', '/v1/authors/${Uri.encodeComponent(name)}')),
  );

  // ---- Gifts ----

  Future<GiftTiers> giftTiers() async =>
      GiftTiers.fromJson(_map(await _send('GET', '/v1/gifts/tiers')));

  Future<Gift> giftApple(String postId, String signedTransaction) async =>
      Gift.fromJson(
        _map(
          await _send(
            'POST',
            '${_post(postId)}/gifts/apple',
            body: {'signed_transaction': signedTransaction},
          ),
        ),
      );

  Future<Gift> giftGoogle(
    String postId,
    String productId,
    String purchaseToken,
  ) async => Gift.fromJson(
    _map(
      await _send(
        'POST',
        '${_post(postId)}/gifts/google',
        body: {'product_id': productId, 'purchase_token': purchaseToken},
      ),
    ),
  );

  // ---- Notifications, streaks, referrals ----

  Future<NotificationsPage> notifications({int limit = 50}) async =>
      NotificationsPage.fromJson(
        _map(
          await _send('GET', '/v1/notifications', query: {'limit': '$limit'}),
        ),
      );

  /// Marks [ids] read, or everything when [ids] is null.
  Future<void> markNotificationsRead([List<String>? ids]) => _send(
    'POST',
    '/v1/notifications/read',
    body: ids == null ? null : {'ids': ids},
  );

  Future<void> registerDevice(String platform, String token) => _send(
    'POST',
    '/v1/devices',
    body: {'platform': platform, 'token': token},
  );

  Future<void> unregisterDevice(String token) =>
      _send('DELETE', '/v1/devices/${Uri.encodeComponent(token)}');

  Future<Streak> streak() async =>
      Streak.fromJson(_map(await _send('GET', '/v1/me/streak')));

  Future<Referrals> referrals() async =>
      Referrals.fromJson(_map(await _send('GET', '/v1/me/referrals')));

  // ---- Blocking ----

  Future<List<BlockedUser>> blocks() async =>
      (_map(await _send('GET', '/v1/me/blocks'))['blocks'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(BlockedUser.fromJson)
          .toList();

  /// [kind] is `block` or `mute`; null clears it.
  Future<void> setBlock(String userId, String? kind) => kind == null
      ? _send('DELETE', '/v1/blocks/${Uri.encodeComponent(userId)}')
      : _send(
          'PUT',
          '/v1/blocks/${Uri.encodeComponent(userId)}',
          body: {'kind': kind},
        );

  // ---- Discover ----

  Future<DiscoverPage> discover() async =>
      DiscoverPage.fromJson(_map(await _send('GET', '/v1/discover')));

  Future<List<Post>> trending({
    String? topic,
    int days = 7,
    int limit = 20,
  }) async => PostPage.fromJson(
    _map(
      await _send(
        'GET',
        '/v1/trending',
        query: {'topic': topic, 'days': '$days', 'limit': '$limit'},
      ),
    ),
  ).posts;

  Future<List<Stash>> userStashes(String handle) async =>
      (_map(
                    await _send(
                      'GET',
                      '/v1/users/${Uri.encodeComponent(handle)}/stashes',
                    ),
                  )['stashes']
                  as List? ??
              const [])
          .whereType<Map<String, dynamic>>()
          .map(Stash.fromJson)
          .toList();

  Future<PublicStash> publicStash(String id) async => PublicStash.fromJson(
    _map(await _send('GET', '/v1/public/stashes/${Uri.encodeComponent(id)}')),
  );

  // ---- Circles ----

  Future<List<Circle>> circles({String? source, bool mine = false}) async =>
      parseCircles(
        _map(
          await _send(
            'GET',
            '/v1/circles',
            query: {'source': source, 'mine': mine ? '1' : null},
          ),
        )['circles'],
      );

  Future<Circle> createCircle(
    String sourceId,
    String name, {
    String? description,
  }) async => Circle.fromJson(
    _map(
      await _send(
        'POST',
        '/v1/circles',
        body: {
          'source_id': sourceId,
          'name': name,
          if (description != null && description.isNotEmpty)
            'description': description,
        },
      ),
    ),
  );

  String _circle(String id) => '/v1/circles/${Uri.encodeComponent(id)}';

  Future<Circle> circle(String id) async =>
      Circle.fromJson(_map(await _send('GET', _circle(id))));

  Future<Circle> joinCircle(String id) async =>
      Circle.fromJson(_map(await _send('POST', '${_circle(id)}/join')));

  Future<void> leaveCircle(String id) => _send('POST', '${_circle(id)}/leave');

  /// Members, owner first.
  Future<List<CircleMember>> circleMembers(String id) async =>
      (_map(await _send('GET', '${_circle(id)}/members'))['members'] as List? ??
              const [])
          .whereType<Map<String, dynamic>>()
          .map(CircleMember.fromJson)
          .toList();

  Future<List<CircleMessage>> circleMessages(
    String id, {
    DateTime? before,
    int limit = 50,
  }) async =>
      (_map(
                    await _send(
                      'GET',
                      '${_circle(id)}/messages',
                      query: {
                        'before': before?.toUtc().toIso8601String(),
                        'limit': '$limit',
                      },
                    ),
                  )['messages']
                  as List? ??
              const [])
          .whereType<Map<String, dynamic>>()
          .map(CircleMessage.fromJson)
          .toList();

  Future<CircleMessage> postCircleMessage(
    String id,
    String body, {
    String? postId,
  }) async => CircleMessage.fromJson(
    _map(
      await _send(
        'POST',
        '${_circle(id)}/messages',
        body: {'body': body, 'post_id': ?postId},
      ),
    ),
  );

  Future<void> deleteCircleMessage(String circleId, String messageId) =>
      _send('DELETE', '${_circle(circleId)}/messages/$messageId');

  // ---- Premium ----

  Future<PremiumStatus> premium() async =>
      PremiumStatus.fromJson(_map(await _send('GET', '/v1/premium')));

  Future<PremiumStatus> premiumApple(String signedTransaction) async =>
      PremiumStatus.fromJson(
        _map(
          await _send(
            'POST',
            '/v1/premium/apple',
            body: {'signed_transaction': signedTransaction},
          ),
        ),
      );

  Future<PremiumStatus> premiumGoogle(
    String productId,
    String purchaseToken,
  ) async => PremiumStatus.fromJson(
    _map(
      await _send(
        'POST',
        '/v1/premium/google',
        body: {'product_id': productId, 'purchase_token': purchaseToken},
      ),
    ),
  );

  // ---- Moderator dashboard ----

  Future<AdminStats> adminStats() async =>
      AdminStats.fromJson(_map(await _send('GET', '/v1/admin/stats')));

  // ---- Stashes ----

  Future<List<Stash>> stashes() async {
    final json = _map(await _send('GET', '/v1/stashes'));
    return (json['stashes'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Stash.fromJson)
        .toList();
  }

  Future<Stash> createStash(
    String name, {
    String? description,
    bool? isPublic,
  }) async => Stash.fromJson(
    _map(
      await _send(
        'POST',
        '/v1/stashes',
        body: {
          'name': name,
          'description': ?description,
          'is_public': ?isPublic,
        },
      ),
    ),
  );

  Future<StashDetail> stash(String id) async =>
      StashDetail.fromJson(_map(await _send('GET', '/v1/stashes/$id')));

  Future<Stash> updateStash(
    String id, {
    String? name,
    String? description,
    bool? isPublic,
  }) async => Stash.fromJson(
    _map(
      await _send(
        'PATCH',
        '/v1/stashes/$id',
        body: {
          'name': ?name,
          'description': ?description,
          'is_public': ?isPublic,
        },
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

  /// Comments people have reported, most reported first; hidden ones too.
  Future<List<ReportedComment>> reportedComments() async =>
      (_map(await _send('GET', '/v1/moderation/comments'))['comments']
                  as List? ??
              const [])
          .whereType<Map<String, dynamic>>()
          .map(ReportedComment.fromJson)
          .toList();

  /// Hides (or restores) a reported comment; either way its reports clear.
  Future<void> moderateComment(String id, {required bool hide}) => _send(
    'POST',
    '/v1/moderation/comments/${Uri.encodeComponent(id)}/${hide ? 'hide' : 'restore'}',
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

  // ---- Reborn AI ----

  /// Replies can take a while: the model may search, draw a chart or make a picture.
  static const aiTimeout = Duration(minutes: 2);

  Future<AIStatus> aiStatus() async =>
      AIStatus.fromJson(_map(await _send('GET', '/v1/ai')));

  Future<AITurn> aiChat(String message, {String? conversationId}) async =>
      AITurn.fromJson(
        _map(
          await _send(
            'POST',
            '/v1/ai/chat',
            body: {'message': message, 'conversation_id': ?conversationId},
            timeout: aiTimeout,
          ),
        ),
      );

  /// Sends a recorded voice message; the server transcribes and answers it.
  Future<AITurn> aiVoice(
    List<int> audio,
    String filename, {
    String? conversationId,
  }) async {
    final req = http.MultipartRequest('POST', _uri('/v1/ai/voice'));
    req.headers['Accept'] = 'application/json';
    final token = _token();
    if (token != null && token.isNotEmpty) {
      req.headers['Authorization'] = 'Bearer $token';
    }
    if (conversationId != null) req.fields['conversation_id'] = conversationId;
    req.files.add(
      http.MultipartFile.fromBytes('audio', audio, filename: filename),
    );
    http.Response res;
    try {
      res = await http.Response.fromStream(
        await _http.send(req).timeout(aiTimeout),
      );
    } on TimeoutException {
      throw const ApiException.network('The request timed out');
    } catch (e) {
      throw const ApiException.network();
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return AITurn.fromJson(_map(jsonDecode(utf8.decode(res.bodyBytes))));
    }
    throw _parseError(res);
  }

  Future<AISpeech> aiSpeech(String messageId) async => AISpeech.fromJson(
    _map(
      await _send(
        'POST',
        '/v1/ai/messages/${Uri.encodeComponent(messageId)}/speech',
        timeout: aiTimeout,
      ),
    ),
  );

  Future<List<AIConversation>> aiConversations() async =>
      (_map(await _send('GET', '/v1/ai/conversations'))['conversations']
                  as List? ??
              const [])
          .whereType<Map<String, dynamic>>()
          .map(AIConversation.fromJson)
          .toList();

  Future<List<AIMessage>> aiConversation(String id) async =>
      (_map(
                    await _send(
                      'GET',
                      '/v1/ai/conversations/${Uri.encodeComponent(id)}',
                    ),
                  )['messages']
                  as List? ??
              const [])
          .whereType<Map<String, dynamic>>()
          .map(AIMessage.fromJson)
          .toList();

  Future<void> deleteAIConversation(String id) =>
      _send('DELETE', '/v1/ai/conversations/${Uri.encodeComponent(id)}');

  Future<AITopUp> topUpApple(String signedTransaction) async =>
      AITopUp.fromJson(
        _map(
          await _send(
            'POST',
            '/v1/ai/topups/apple',
            body: {'signed_transaction': signedTransaction},
          ),
        ),
      );

  Future<AITopUp> topUpGoogle(String productId, String purchaseToken) async =>
      AITopUp.fromJson(
        _map(
          await _send(
            'POST',
            '/v1/ai/topups/google',
            body: {'product_id': productId, 'purchase_token': purchaseToken},
          ),
        ),
      );
}
