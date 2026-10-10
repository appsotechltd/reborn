import 'dart:async';

import '../api/api_client.dart';
import '../api/models.dart';
import 'offline_cache.dart';

/// A value plus whether it came from the offline cache.
class Fetched<T> {
  const Fetched(this.value, {this.offline = false});
  final T value;
  final bool offline;
}

/// The nine topics from content/SCHEMA.md, used when /v1/topics is
/// unreachable and nothing is cached yet.
const kDefaultTopics = <Topic>[
  Topic(slug: 'business', name: 'Business'),
  Topic(slug: 'psychology', name: 'Psychology'),
  Topic(slug: 'health', name: 'Health & Wellness'),
  Topic(slug: 'emotional-intelligence', name: 'Emotional Intelligence'),
  Topic(slug: 'personal-development', name: 'Personal Development'),
  Topic(slug: 'productivity', name: 'Productivity & Career'),
  Topic(slug: 'money', name: 'Money'),
  Topic(slug: 'relationships', name: 'Relationships'),
  Topic(slug: 'mindfulness', name: 'Mindfulness & Philosophy'),
];

/// Wraps [ApiClient] with the offline cache: reads go to the network first;
/// when the network is unreachable they fall back to the last cached copy.
class RebornRepository {
  RebornRepository(
    this.api,
    this.cache, {
    this.onConnectivity,
    this.onUnauthorized,
  });

  final ApiClient api;
  final OfflineCache cache;

  /// Called with `true` when a request fails for network reasons and `false`
  /// when one succeeds.
  final void Function(bool offline)? onConnectivity;

  /// Called when an authenticated request returns 401.
  final void Function()? onUnauthorized;

  void _setOffline(bool offline) => onConnectivity?.call(offline);

  /// Runs [call], tracking connectivity and 401s.
  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      final v = await call();
      _setOffline(false);
      return v;
    } on ApiException catch (e) {
      if (e.isNetwork) {
        _setOffline(true);
      } else {
        _setOffline(false);
        if (e.isUnauthorized) onUnauthorized?.call();
      }
      rethrow;
    }
  }

  /// Network first; on a network failure serve the cached JSON at [key].
  Future<Fetched<T>> _cached<T>(
    String key,
    Future<T> Function() fetch,
    Object? Function(T) encode,
    T Function(dynamic json) decode,
  ) async {
    try {
      final v = await _run(fetch);
      await cache.write(key, encode(v));
      return Fetched(v);
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
      final json = cache.read(key);
      if (json == null) rethrow;
      try {
        return Fetched(decode(json), offline: true);
      } catch (_) {
        throw e;
      }
    }
  }

  // ---- Library ----

  Future<Fetched<List<Topic>>> topics() async {
    try {
      return await _cached<List<Topic>>(
        OfflineCache.topicsKey,
        api.topics,
        (v) => v.map((t) => t.toJson()).toList(),
        (j) => (j as List)
            .whereType<Map<String, dynamic>>()
            .map(Topic.fromJson)
            .toList(),
      );
    } on ApiException catch (e) {
      if (e.isNetwork) return const Fetched(kDefaultTopics, offline: true);
      rethrow;
    }
  }

  Future<Fetched<FeedPage>> feed({List<String>? topics, String? cursor}) async {
    final r = await _cached<FeedPage>(
      OfflineCache.feedKey(topics, cursor),
      () => api.feed(topics: topics, cursor: cursor),
      (v) => v.toJson(),
      (j) => FeedPage.fromJson(j as Map<String, dynamic>),
    );
    if (!r.offline) await cache.putCards(r.value.cards);
    return r;
  }

  Future<Fetched<DailyIdea>> daily() async {
    final r = await _cached<DailyIdea>(
      OfflineCache.dailyKey,
      api.daily,
      (v) => v.toJson(),
      (j) => DailyIdea.fromJson(j as Map<String, dynamic>),
    );
    if (!r.offline) await cache.putCard(r.value.card);
    return r;
  }

  Future<Fetched<IdeaCard>> card(String id) => _cached<IdeaCard>(
    OfflineCache.cardKey(id),
    () => api.card(id),
    (v) => v.toJson(),
    (j) => IdeaCard.fromJson(j as Map<String, dynamic>),
  );

  /// Stores a card the user opened so it can be read offline later.
  Future<void> rememberCard(IdeaCard card) => cache.putCard(card);

  Future<Fetched<SourceDetail>> source(String id) async {
    final r = await _cached<SourceDetail>(
      OfflineCache.sourceKey(id),
      () => api.source(id),
      (v) => v.toJson(),
      (j) => SourceDetail.fromJson(j as Map<String, dynamic>),
    );
    return r;
  }

  Future<List<IdeaCard>> search(String q, {String? topic}) =>
      _run(() => api.search(q, topic: topic));

  Future<void> recordView(String cardId) async {
    try {
      await _run(() => api.recordView(cardId));
    } on ApiException {
      // Best effort.
    }
  }

  // ---- Account ----

  Future<AuthResult> login(String email, String password) =>
      _run(() => api.login(email, password));

  Future<AuthResult> register(String email, String password, String name) =>
      _run(() => api.register(email, password, name));

  Future<User> me() => _run(api.me);

  Future<User> updateMe({
    String? displayName,
    String? handle,
    String? bio,
    List<String>? topics,
  }) => _run(
    () => api.updateMe(
      displayName: displayName,
      handle: handle,
      bio: bio,
      topics: topics,
    ),
  );

  Future<void> deleteMe() => _run(api.deleteMe);

  Future<void> forgotPassword(String email) =>
      _run(() => api.forgotPassword(email));

  // ---- Social ----

  Future<Fetched<PostPage>> timeline({
    List<String>? topics,
    String? cursor,
  }) async {
    final r = await _cached<PostPage>(
      OfflineCache.timelineKey(topics, cursor),
      () => api.timeline(topics: topics, cursor: cursor),
      (v) => v.toJson(),
      (j) => PostPage.fromJson(j as Map<String, dynamic>),
    );
    if (!r.offline) await cache.putCards(r.value.posts.map((p) => p.card));
    return r;
  }

  /// Best effort: losing a "seen" mark only means seeing a post again.
  Future<void> markSeen(List<String> postIds) async {
    if (postIds.isEmpty) return;
    try {
      await _run(() => api.markSeen(postIds));
    } on ApiException {
      // Ignore.
    }
  }

  /// A post; offline, the cached post or else the cached card without stats.
  Future<Fetched<Post>> post(String id) async {
    try {
      return await _cached<Post>(
        OfflineCache.postKey(id),
        () => api.post(id),
        (v) => v.toJson(),
        (j) => Post.fromJson(j as Map<String, dynamic>),
      );
    } on ApiException catch (e) {
      final card = e.isNetwork ? cache.getCard(id) : null;
      if (card == null) rethrow;
      return Fetched(Post.fromCard(card), offline: true);
    }
  }

  Future<void> setFavorite(String postId, bool on) =>
      _run(() => api.setFavorite(postId, on));

  Future<void> setReaction(String postId, Reaction? kind) =>
      _run(() => api.setReaction(postId, kind));

  /// Counts a share; never fails the share itself.
  Future<void> recordShare(String postId, String channel) async {
    try {
      await _run(() => api.share(postId, channel));
    } on ApiException {
      // Best effort.
    }
  }

  Future<CommentPage> comments(String postId, {String? cursor}) =>
      _run(() => api.comments(postId, cursor: cursor));

  Future<Comment> addComment(String postId, String body, {String? parentId}) =>
      _run(() => api.addComment(postId, body, parentId: parentId));

  Future<void> deleteComment(String id) => _run(() => api.deleteComment(id));

  Future<void> reportComment(String id, {String? reason}) =>
      _run(() => api.reportComment(id, reason: reason));

  Future<PostPage> myFavorites({String? cursor}) =>
      _run(() => api.myFavorites(cursor: cursor));

  Future<List<FollowItem>> following() => _run(api.following);

  Future<FollowState> setFollow(FollowKind kind, String target, bool on) =>
      _run(() => api.setFollow(kind, target, on));

  Future<Profile> profile(String handle) => _run(() => api.profile(handle));

  Future<PostPage> userFavorites(String handle, {String? cursor}) =>
      _run(() => api.userFavorites(handle, cursor: cursor));

  Future<AuthorPage> author(String name) => _run(() => api.author(name));

  Future<GiftTiers> giftTiers() => _run(api.giftTiers);

  Future<Gift> giftApple(String postId, String signedTransaction) =>
      _run(() => api.giftApple(postId, signedTransaction));

  Future<Gift> giftGoogle(
    String postId,
    String productId,
    String purchaseToken,
  ) => _run(() => api.giftGoogle(postId, productId, purchaseToken));

  // ---- Stashes ----

  Future<Fetched<List<Stash>>> stashes() async {
    final r = await _cached<List<Stash>>(
      OfflineCache.stashesKey,
      api.stashes,
      (v) => v.map((s) => s.toJson()).toList(),
      (j) => (j as List)
          .whereType<Map<String, dynamic>>()
          .map(Stash.fromJson)
          .toList(),
    );
    if (!r.offline) unawaited(_prefetchStashes(r.value));
    return r;
  }

  /// Caches every stash with its cards so stashed cards read offline even if
  /// the stash was never opened.
  Future<void> _prefetchStashes(List<Stash> stashes) async {
    for (final s in stashes) {
      try {
        await stash(s.id);
      } catch (_) {
        return;
      }
    }
  }

  Future<Fetched<StashDetail>> stash(String id) async {
    final r = await _cached<StashDetail>(
      OfflineCache.stashKey(id),
      () => api.stash(id),
      (v) => v.toJson(),
      (j) => StashDetail.fromJson(j as Map<String, dynamic>),
    );
    if (!r.offline) await cache.putCards(r.value.cards);
    return r;
  }

  Future<Stash> createStash(String name, {String? description}) =>
      _run(() => api.createStash(name, description: description));

  Future<Stash> renameStash(String id, String name, {String? description}) =>
      _run(() => api.updateStash(id, name: name, description: description));

  Future<void> deleteStash(String id) async {
    await _run(() => api.deleteStash(id));
    await cache.remove(OfflineCache.stashKey(id));
  }

  Future<void> addToStash(String stashId, IdeaCard card) async {
    await _run(() => api.addToStash(stashId, card.id));
    await cache.putCard(card);
    // Refresh the cached copy so the new card is readable offline.
    unawaited(stash(stashId).then((_) {}, onError: (_) {}));
  }

  Future<void> removeFromStash(String stashId, String cardId) =>
      _run(() => api.removeFromStash(stashId, cardId));

  // ---- Review / quiz ----

  Future<ReviewDue> reviewDue({int limit = 20}) =>
      _run(() => api.reviewDue(limit: limit));

  Future<ReviewResult> review(String cardId, Grade grade) =>
      _run(() => api.review(cardId, grade));

  Future<List<IdeaCard>> quiz({String? topic, int limit = 5}) =>
      _run(() => api.quiz(topic: topic, limit: limit));

  // ---- Contributions ----

  Future<Contribution> contribute(ContributionDraft draft) =>
      _run(() => api.contribute(draft));

  Future<List<Contribution>> myContributions() => _run(api.myContributions);

  Future<List<Contribution>> moderationQueue() => _run(api.moderationQueue);

  Future<Contribution> approve(String id, {String? note}) =>
      _run(() => api.approve(id, note: note));

  Future<Contribution> reject(String id, String note) =>
      _run(() => api.reject(id, note));

  // ---- Agent ----

  Future<ChatReply> chat(List<ChatMessage> messages) =>
      _run(() => api.chat(messages));
}
