import 'dart:async';

import '../api/api_client.dart';
import '../api/ai_models.dart';
import '../api/member_models.dart';
import '../api/models.dart';
import 'offline_cache.dart';

/// A value plus whether it came from the offline cache.
class Fetched<T> {
  const Fetched(this.value, {this.offline = false});
  final T value;
  final bool offline;
}

/// The topics from content/SCHEMA.md, used when /v1/topics is
/// unreachable and nothing is cached yet.
const kDefaultTopics = <Topic>[
  Topic(slug: 'business', name: 'Business'),
  Topic(slug: 'psychology', name: 'Psychology'),
  Topic(slug: 'mental-strength', name: 'Mental Strength & Resilience'),
  Topic(slug: 'health', name: 'Health & Wellness'),
  Topic(slug: 'emotional-intelligence', name: 'Emotional Intelligence'),
  Topic(slug: 'personal-development', name: 'Personal Development'),
  Topic(slug: 'productivity', name: 'Productivity & Career'),
  Topic(slug: 'money', name: 'Money'),
  Topic(slug: 'relationships', name: 'Relationships'),
  Topic(slug: 'dating-marriage', name: 'Dating & Marriage'),
  Topic(slug: 'mindfulness', name: 'Mindfulness & Philosophy'),
  Topic(slug: 'faith-wisdom', name: 'Faith & Wisdom'),
  Topic(slug: 'leadership', name: 'Leadership'),
  Topic(slug: 'parenting', name: 'Parenting & Family'),
  Topic(slug: 'communication', name: 'Communication & Influence'),
  Topic(slug: 'creativity', name: 'Creativity'),
  Topic(slug: 'learning', name: 'Learning & Thinking'),
  Topic(slug: 'lives-history', name: 'Lives & History'),
  Topic(slug: 'entrepreneurship', name: 'Entrepreneurship'),
  Topic(slug: 'heartbreak-healing', name: 'Heartbreak & Healing'),
  Topic(slug: 'grief-loss', name: 'Grief & Loss'),
  Topic(slug: 'study-smarter', name: 'Study Smarter'),
  Topic(slug: 'skills-mastery', name: 'Skills & Mastery'),
  Topic(slug: 'etiquette', name: 'Etiquette & Manners'),
  Topic(slug: 'mental-health', name: 'Mental Health'),
  Topic(slug: 'ai-skills', name: 'AI & Future Skills'),
  Topic(slug: 'science', name: 'Science & Nature'),
  Topic(slug: 'crime-society', name: 'Crime & Society'),
  Topic(slug: 'universe', name: 'Wonders of the Universe'),
  Topic(slug: 'life-guides', name: 'Life Guides'),
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

  Future<AuthResult> register(
    String email,
    String password,
    String name, {
    String? timezone,
    String? referralCode,
  }) => _run(
    () => api.register(
      email,
      password,
      name,
      timezone: timezone,
      referralCode: referralCode,
    ),
  );

  Future<User> me() => _run(api.me);

  Future<User> updateMe({
    String? displayName,
    String? handle,
    String? bio,
    List<String>? topics,
    String? timezone,
    int? dailyGoal,
    Map<String, bool>? notify,
  }) => _run(
    () => api.updateMe(
      displayName: displayName,
      handle: handle,
      bio: bio,
      topics: topics,
      timezone: timezone,
      dailyGoal: dailyGoal,
      notify: notify,
    ),
  );

  Future<void> deleteMe() => _run(api.deleteMe);

  Future<void> forgotPassword(String email) =>
      _run(() => api.forgotPassword(email));

  // ---- Social ----

  /// The timeline. With [withSummaries] (the home feed) summary posts come
  /// woven in; Listen mode pages through card posts only.
  Future<Fetched<PostPage>> timeline({
    List<String>? topics,
    String? media,
    String? cursor,
    bool withSummaries = false,
  }) async {
    final key = OfflineCache.timelineKey(topics, cursor, media: media);
    final r = await _cached<PostPage>(
      withSummaries ? '$key.s' : key,
      () => api.timeline(
        topics: topics,
        media: media,
        cursor: cursor,
        withSummaries: withSummaries,
      ),
      (v) => v.toJson(),
      (j) => PostPage.fromJson(j as Map<String, dynamic>),
    );
    if (!r.offline) {
      await cache.putCards(
        r.value.posts.where((p) => !p.isSummary).map((p) => p.card),
      );
    }
    return r;
  }

  /// A summary and its parts; kept for reading offline.
  Future<Fetched<SummaryDetail>> summary(String id) => _cached<SummaryDetail>(
    'summary.$id',
    () => api.summary(id),
    (v) => v.toJson(),
    (j) => SummaryDetail.fromJson(j as Map<String, dynamic>),
  );

  Future<Fetched<SummaryPage>> summaries() => _cached<SummaryPage>(
    'summaries',
    () => api.summaries(limit: 50).then((first) async {
      // Every summary: there are about a hundred, a few pages at most.
      final all = [...first.summaries];
      var cursor = first.nextCursor;
      while (cursor != null && all.length < 500) {
        final page = await api.summaries(cursor: cursor, limit: 50);
        all.addAll(page.summaries);
        cursor = page.nextCursor;
      }
      return SummaryPage(summaries: all);
    }),
    (v) => v.toJson(),
    (j) => SummaryPage.fromJson(j as Map<String, dynamic>),
  );

  /// Best effort: the place is also kept on the device.
  Future<SummaryProgress?> setSummaryProgress(
    String id,
    int position, {
    bool finished = false,
  }) async {
    try {
      return await _run(
        () => api.setSummaryProgress(id, position, finished: finished),
      );
    } on ApiException {
      return null;
    }
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

  /// A page of the library's books.
  Future<SourceListPage> sources({String? topic, String? q, String? cursor}) =>
      _run(() => api.sources(topic: topic, q: q, cursor: cursor));

  /// A page of the library's authors.
  Future<AuthorListPage> authors({String? topic, String? q, String? cursor}) =>
      _run(() => api.authors(topic: topic, q: q, cursor: cursor));

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

  Future<Stash> setStashPublic(String id, bool isPublic) =>
      _run(() => api.updateStash(id, isPublic: isPublic));

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

  Future<List<ReportedComment>> reportedComments() =>
      _run(api.reportedComments);

  Future<void> moderateComment(String id, {required bool hide}) =>
      _run(() => api.moderateComment(id, hide: hide));

  // ---- Agent ----

  Future<ChatReply> chat(List<ChatMessage> messages) =>
      _run(() => api.chat(messages));

  // ---- Notifications, streaks, referrals ----

  Future<NotificationsPage> notifications() => _run(api.notifications);

  Future<void> markNotificationsRead([List<String>? ids]) =>
      _run(() => api.markNotificationsRead(ids));

  Future<void> registerDevice(String platform, String token) =>
      _run(() => api.registerDevice(platform, token));

  Future<void> unregisterDevice(String token) =>
      _run(() => api.unregisterDevice(token));

  Future<Streak> streak() => _run(api.streak);

  Future<Referrals> referrals() => _run(api.referrals);

  // ---- Blocking ----

  Future<List<BlockedUser>> blocks() => _run(api.blocks);

  Future<void> setBlock(String userId, String? kind) =>
      _run(() => api.setBlock(userId, kind));

  // ---- Discover ----

  Future<DiscoverPage> discover() => _run(api.discover);

  Future<List<Post>> trending({String? topic}) =>
      _run(() => api.trending(topic: topic));

  Future<List<Stash>> userStashes(String handle) =>
      _run(() => api.userStashes(handle));

  Future<PublicStash> publicStash(String id) => _run(() => api.publicStash(id));

  // ---- Circles ----

  Future<List<Circle>> circles({String? source, bool mine = false}) =>
      _run(() => api.circles(source: source, mine: mine));

  Future<Circle> createCircle(
    String sourceId,
    String name, {
    String? description,
  }) => _run(() => api.createCircle(sourceId, name, description: description));

  Future<Circle> circle(String id) => _run(() => api.circle(id));

  Future<Circle> joinCircle(String id) => _run(() => api.joinCircle(id));

  Future<void> leaveCircle(String id) => _run(() => api.leaveCircle(id));

  Future<List<CircleMember>> circleMembers(String id) =>
      _run(() => api.circleMembers(id));

  Future<List<CircleMessage>> circleMessages(String id, {DateTime? before}) =>
      _run(() => api.circleMessages(id, before: before));

  Future<CircleMessage> postCircleMessage(
    String id,
    String body, {
    String? postId,
  }) => _run(() => api.postCircleMessage(id, body, postId: postId));

  Future<void> deleteCircleMessage(String circleId, String messageId) =>
      _run(() => api.deleteCircleMessage(circleId, messageId));

  // ---- Premium ----

  Future<PremiumStatus> premium() => _run(api.premium);

  Future<PremiumStatus> premiumApple(String signedTransaction) =>
      _run(() => api.premiumApple(signedTransaction));

  Future<PremiumStatus> premiumGoogle(String productId, String purchaseToken) =>
      _run(() => api.premiumGoogle(productId, purchaseToken));

  // ---- Moderator dashboard ----

  Future<AdminStats> adminStats() => _run(api.adminStats);

  // ---- Reborn AI ----

  Future<AIStatus> aiStatus() => _run(api.aiStatus);

  Future<AITurn> aiChat(String message, {String? conversationId}) =>
      _run(() => api.aiChat(message, conversationId: conversationId));

  Future<AITurn> aiVoice(
    List<int> audio,
    String filename, {
    String? conversationId,
  }) =>
      _run(() => api.aiVoice(audio, filename, conversationId: conversationId));

  Future<AISpeech> aiSpeech(String messageId) =>
      _run(() => api.aiSpeech(messageId));

  Future<List<AIConversation>> aiConversations() => _run(api.aiConversations);

  Future<List<AIMessage>> aiConversation(String id) =>
      _run(() => api.aiConversation(id));

  Future<void> deleteAIConversation(String id) =>
      _run(() => api.deleteAIConversation(id));

  Future<AITopUp> topUpApple(String signedTransaction) =>
      _run(() => api.topUpApple(signedTransaction));

  Future<AITopUp> topUpGoogle(String productId, String purchaseToken) =>
      _run(() => api.topUpGoogle(productId, purchaseToken));

  // ---- Member cards, categories and the card studio ----

  Future<List<CardCategory>> myCategories() => _run(api.myCategories);

  Future<CardCategory> createCategory(String name) =>
      _run(() => api.createCategory(name));

  Future<CardCategory> renameCategory(String id, String name) =>
      _run(() => api.renameCategory(id, name));

  Future<void> deleteCategory(String id) => _run(() => api.deleteCategory(id));

  Future<MyCardsPage> myCards({String? category, String? cursor}) =>
      _run(() => api.myCards(category: category, cursor: cursor));

  Future<IdeaCard> myCard(String id) => _run(() => api.myCard(id));

  Future<IdeaCard> createMyCard(Map<String, Object?> fields) =>
      _run(() => api.createMyCard(fields));

  Future<IdeaCard> updateMyCard(String id, Map<String, Object?> fields) =>
      _run(() => api.updateMyCard(id, fields));

  Future<void> deleteMyCard(String id) => _run(() => api.deleteMyCard(id));

  Future<UserCardsPage> userCards(
    String handle, {
    String? category,
    String? cursor,
  }) => _run(() => api.userCards(handle, category: category, cursor: cursor));

  Future<void> reportPost(String postId, {String? reason}) =>
      _run(() => api.reportPost(postId, reason: reason));

  Future<List<ReportedCard>> reportedCards() => _run(api.reportedCards);

  Future<void> moderateCard(String id, {required bool hide}) =>
      _run(() => api.moderateCard(id, hide: hide));

  Future<StudioStatus> studio() => _run(api.studio);

  Future<StudioResult> makeCardImage(
    String id, {
    required String style,
    String? prompt,
    String? shape,
  }) => _run(
    () => api.makeCardImage(id, style: style, prompt: prompt, shape: shape),
  );

  Future<StudioResult> makeCardAudio(String id, {String? voice}) =>
      _run(() => api.makeCardAudio(id, voice: voice));

  Future<StudioResult> makeCardVideo(String id, {String? voice}) =>
      _run(() => api.makeCardVideo(id, voice: voice));

  Future<IdeaCard> deleteCardMedia(String id, String kind) =>
      _run(() => api.deleteCardMedia(id, kind));

  // ---- Writer earnings and subscriptions ----

  Future<Earnings> earnings() => _run(api.earnings);

  Future<MyWriterPlan> myPlan() => _run(api.myPlan);

  Future<WriterPlan> setMyPlan({
    required String tier,
    required bool enabled,
    String pitch = '',
  }) => _run(() => api.setMyPlan(tier: tier, enabled: enabled, pitch: pitch));

  Future<List<WriterSubscription>> mySubscriptions() =>
      _run(api.mySubscriptions);

  Future<WriterOffer> writerOffer(String handle) =>
      _run(() => api.writerOffer(handle));

  Future<WriterSubscription> subscribeApple(
    String handle,
    String signedTransaction,
  ) => _run(() => api.subscribeApple(handle, signedTransaction));

  Future<WriterSubscription> subscribeGoogle(
    String handle,
    String productId,
    String purchaseToken,
  ) => _run(() => api.subscribeGoogle(handle, productId, purchaseToken));

  Future<WriterSubscription> cancelSubscription(String handle) =>
      _run(() => api.cancelSubscription(handle));
}
