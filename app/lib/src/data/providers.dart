import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import 'offline_cache.dart';
import 'repository.dart';

/// Overridden in `main()` with the loaded instance (and in tests).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPreferencesProvider not overridden'),
);

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    httpClient: ref.watch(httpClientProvider),
    token: () => ref.read(sessionProvider).token,
  ),
);

final offlineCacheProvider = Provider<OfflineCache>(
  (ref) => OfflineCache(ref.watch(sharedPreferencesProvider)),
);

/// True while the last request failed because the network was unreachable.
class OfflineNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool offline) {
    if (state != offline) state = offline;
  }
}

final offlineProvider = NotifierProvider<OfflineNotifier, bool>(
  OfflineNotifier.new,
);

final repositoryProvider = Provider<RebornRepository>(
  (ref) => RebornRepository(
    ref.watch(apiClientProvider),
    ref.watch(offlineCacheProvider),
    onConnectivity: (offline) =>
        Future.microtask(() => ref.read(offlineProvider.notifier).set(offline)),
    onUnauthorized: () =>
        Future.microtask(() => ref.read(sessionProvider.notifier).signOut()),
  ),
);

// ---------------------------------------------------------------------------
// Session

class Session {
  const Session({this.token, this.user});
  final String? token;
  final User? user;

  bool get signedIn => token != null && token!.isNotEmpty;
  bool get isModerator => user?.isModerator ?? false;
}

class SessionController extends Notifier<Session> {
  static const tokenKey = 'auth.token';
  static const userKey = 'auth.user';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  Session build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final token = prefs.getString(tokenKey);
    User? user;
    final rawUser = prefs.getString(userKey);
    if (rawUser != null) {
      try {
        user = User.fromJson(jsonDecode(rawUser) as Map<String, dynamic>);
      } catch (_) {}
    }
    return Session(token: token, user: user);
  }

  Future<void> _store(AuthResult r) async {
    await _prefs.setString(tokenKey, r.token);
    await _prefs.setString(userKey, jsonEncode(r.user.toJson()));
    state = Session(token: r.token, user: r.user);
  }

  Future<void> signIn(String email, String password) async {
    final r = await ref.read(repositoryProvider).login(email, password);
    await _store(r);
    await ref.read(topicPrefsProvider.notifier).syncAfterSignIn();
  }

  Future<void> register(String email, String password, String name) async {
    final r = await ref
        .read(repositoryProvider)
        .register(email, password, name);
    await _store(r);
    await ref.read(topicPrefsProvider.notifier).syncAfterSignIn();
  }

  Future<void> setUser(User user) async {
    await _prefs.setString(userKey, jsonEncode(user.toJson()));
    state = Session(token: state.token, user: user);
  }

  /// Refreshes the user from GET /v1/me (role/topics may change server side).
  Future<void> refreshUser() async {
    if (!state.signedIn) return;
    try {
      await setUser(await ref.read(repositoryProvider).me());
    } on ApiException {
      // Keep the cached user when offline.
    }
  }

  /// DELETE /v1/me, then signs out on this device.
  Future<void> deleteAccount() async {
    await ref.read(repositoryProvider).deleteMe();
    await signOut();
  }

  Future<void> signOut() async {
    if (!state.signedIn) return;
    await _prefs.remove(tokenKey);
    await _prefs.remove(userKey);
    await ref.read(offlineCacheProvider).clearUserData();
    state = const Session();
  }
}

final sessionProvider = NotifierProvider<SessionController, Session>(
  SessionController.new,
);

// ---------------------------------------------------------------------------
// Topic preferences

class TopicPrefsController extends Notifier<List<String>> {
  static const localKey = 'topics.selected';
  static const onboardedKey = 'onboarding.done';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  List<String> build() {
    final session = ref.watch(sessionProvider);
    if (session.signedIn &&
        session.user != null &&
        session.user!.topics.isNotEmpty) {
      return session.user!.topics;
    }
    return ref.watch(sharedPreferencesProvider).getStringList(localKey) ??
        const [];
  }

  bool get onboarded => _prefs.getBool(onboardedKey) ?? false;

  /// Saves locally, and via PATCH /v1/me when signed in.
  Future<void> save(List<String> topics) async {
    await _prefs.setStringList(localKey, topics);
    await _prefs.setBool(onboardedKey, true);
    state = topics;
    final session = ref.read(sessionProvider);
    if (session.signedIn) {
      final user = await ref.read(repositoryProvider).updateMe(topics: topics);
      await ref.read(sessionProvider.notifier).setUser(user);
    }
  }

  Future<void> markOnboarded() => _prefs.setBool(onboardedKey, true);

  /// After sign-in: if the account has no topics yet, push the local choice.
  Future<void> syncAfterSignIn() async {
    final user = ref.read(sessionProvider).user;
    final local = _prefs.getStringList(localKey) ?? const [];
    if (user != null && user.topics.isEmpty && local.isNotEmpty) {
      try {
        final updated = await ref
            .read(repositoryProvider)
            .updateMe(topics: local);
        await ref.read(sessionProvider.notifier).setUser(updated);
      } on ApiException {
        // Not fatal.
      }
    }
  }
}

final topicPrefsProvider = NotifierProvider<TopicPrefsController, List<String>>(
  TopicPrefsController.new,
);

// ---------------------------------------------------------------------------
// Read-side providers

final topicsProvider = FutureProvider<List<Topic>>(
  (ref) async => (await ref.watch(repositoryProvider).topics()).value,
);

/// slug -> display name.
final topicNamesProvider = Provider<Map<String, String>>((ref) {
  final topics = ref.watch(topicsProvider).value ?? kDefaultTopics;
  return {for (final t in topics) t.slug: t.name};
});

final dailyProvider = FutureProvider.autoDispose<Fetched<DailyIdea>>(
  (ref) => ref.watch(repositoryProvider).daily(),
);

final cardProvider = FutureProvider.autoDispose
    .family<Fetched<IdeaCard>, String>(
      (ref, id) => ref.watch(repositoryProvider).card(id),
    );

final sourceProvider = FutureProvider.autoDispose
    .family<Fetched<SourceDetail>, String>((ref, id) {
      // Re-fetch on sign-in/out: `follow` is personal.
      ref.watch(sessionProvider.select((s) => s.token));
      return ref.watch(repositoryProvider).source(id);
    });

final stashesProvider = FutureProvider.autoDispose<Fetched<List<Stash>>>((ref) {
  ref.watch(sessionProvider.select((s) => s.token));
  return ref.watch(repositoryProvider).stashes();
});

final stashDetailProvider = FutureProvider.autoDispose
    .family<Fetched<StashDetail>, String>(
      (ref, id) => ref.watch(repositoryProvider).stash(id),
    );

final reviewDueProvider = FutureProvider.autoDispose<ReviewDue>((ref) {
  ref.watch(sessionProvider.select((s) => s.token));
  return ref.watch(repositoryProvider).reviewDue();
});

final myContributionsProvider = FutureProvider.autoDispose<List<Contribution>>(
  (ref) => ref.watch(repositoryProvider).myContributions(),
);

final moderationQueueProvider = FutureProvider.autoDispose<List<Contribution>>(
  (ref) => ref.watch(repositoryProvider).moderationQueue(),
);

// ---------------------------------------------------------------------------
// Social read-side providers

final postProvider = FutureProvider.autoDispose.family<Fetched<Post>, String>((
  ref,
  id,
) {
  ref.watch(sessionProvider.select((s) => s.token));
  return ref.watch(repositoryProvider).post(id);
});

final profileProvider = FutureProvider.autoDispose.family<Profile, String>((
  ref,
  handle,
) {
  ref.watch(sessionProvider.select((s) => s.token));
  return ref.watch(repositoryProvider).profile(handle);
});

final authorProvider = FutureProvider.autoDispose.family<AuthorPage, String>((
  ref,
  name,
) {
  ref.watch(sessionProvider.select((s) => s.token));
  return ref.watch(repositoryProvider).author(name);
});

final followingProvider = FutureProvider.autoDispose<List<FollowItem>>((ref) {
  ref.watch(sessionProvider.select((s) => s.token));
  return ref.watch(repositoryProvider).following();
});

final giftTiersProvider = FutureProvider.autoDispose<GiftTiers>(
  (ref) => ref.watch(repositoryProvider).giftTiers(),
);
