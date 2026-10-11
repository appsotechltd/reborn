import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../router.dart';
import 'notifications_controller.dart';

/// Push messaging, behind an interface so it stays optional and testable.
abstract class PushMessaging {
  /// `ios` or `android`.
  String get platform;

  /// Sets up the messaging SDK; false when the app has no Firebase config.
  Future<bool> init();
  Future<bool> requestPermission();
  Future<String?> getToken();
  Stream<String> get onTokenRefresh;

  /// Data of notifications the person tapped while the app was running.
  Stream<Map<String, dynamic>> get onOpened;

  /// Data of the notification that launched the app, if any.
  Future<Map<String, dynamic>?> initialMessage();

  /// Data of messages that arrive while the app is in the foreground.
  Stream<Map<String, dynamic>> get onForeground;
}

/// Firebase Cloud Messaging. Nothing touches Firebase until [init].
class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging(this.platform);

  @override
  final String platform;

  FirebaseMessaging get _fm => FirebaseMessaging.instance;

  @override
  Future<bool> init() async {
    try {
      // Reads google-services.json / GoogleService-Info.plist; throws when
      // they aren't bundled.
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    final s = await _fm.requestPermission();
    return s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> getToken() => _fm.getToken();

  @override
  Stream<String> get onTokenRefresh => _fm.onTokenRefresh;

  @override
  Stream<Map<String, dynamic>> get onOpened =>
      FirebaseMessaging.onMessageOpenedApp.map((m) => m.data);

  @override
  Future<Map<String, dynamic>?> initialMessage() async =>
      (await _fm.getInitialMessage())?.data;

  @override
  Stream<Map<String, dynamic>> get onForeground =>
      FirebaseMessaging.onMessage.map((m) => m.data);
}

/// FCM on iOS and Android; no push on web or desktop.
PushMessaging? createPushMessaging() {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS => FirebasePushMessaging('ios'),
    TargetPlatform.android => FirebasePushMessaging('android'),
    _ => null,
  };
}

/// Where a push message's data (`post_id`, `comment_id`, `circle_id`,
/// `kind`) leads.
String? pushLocation(Map<String, dynamic> data) {
  String? s(String k) => data[k]?.toString();
  return notificationLocation(
        postId: s('post_id'),
        commentId: s('comment_id'),
        circleId: s('circle_id'),
        actorHandle: s('actor_handle'),
      ) ??
      (data.isEmpty ? null : '/notifications');
}

/// Registers the device for push after sign-in and removes it on sign-out.
/// Without Firebase config everything here is a quiet no-op.
class PushService {
  PushService({
    required this.messaging,
    required this.repo,
    required this.signedIn,
    required this.onOpen,
    required this.onMessage,
  });

  final PushMessaging? messaging;
  final RebornRepository repo;
  final bool Function() signedIn;
  final void Function(String location) onOpen;
  final void Function() onMessage;

  bool _ready = false;
  String? _token;
  final _subs = <StreamSubscription<Object?>>[];

  /// The registered token, if any.
  String? get token => _token;

  Future<void> start() async {
    final m = messaging;
    if (m == null || _ready) return;
    try {
      _ready = await m.init();
      if (!_ready) return;
      _subs
        ..add(m.onOpened.listen(_open))
        ..add(m.onForeground.listen((_) => onMessage()))
        ..add(
          m.onTokenRefresh.listen((t) {
            if (_token != null) unawaited(_register(t));
          }),
        );
      final initial = await m.initialMessage();
      if (initial != null) _open(initial);
      if (signedIn()) await onSignedIn();
    } catch (_) {
      _ready = false;
    }
  }

  void _open(Map<String, dynamic> data) {
    onMessage();
    final loc = pushLocation(data);
    if (loc != null) onOpen(loc);
  }

  /// Asks for permission and registers the token with the server.
  Future<void> onSignedIn() async {
    final m = messaging;
    if (m == null || !_ready) return;
    try {
      if (!await m.requestPermission()) return;
      final t = await m.getToken();
      if (t != null && t.isNotEmpty) await _register(t);
    } catch (_) {
      // Push is optional.
    }
  }

  Future<void> _register(String t) async {
    await repo.registerDevice(messaging!.platform, t);
    _token = t;
  }

  /// Removes this device's token; call before the session is cleared.
  Future<void> unregister() async {
    final t = _token;
    _token = null;
    if (t == null) return;
    try {
      await repo.unregisterDevice(t);
    } catch (_) {
      // The server drops dead tokens anyway.
    }
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
  }
}

final pushMessagingProvider = Provider<PushMessaging?>(
  (ref) => createPushMessaging(),
);

final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService(
    messaging: ref.watch(pushMessagingProvider),
    repo: ref.watch(repositoryProvider),
    signedIn: () => ref.read(sessionProvider).signedIn,
    onOpen: (loc) => ref.read(routerProvider).push(loc),
    onMessage: () => ref.invalidate(notificationsProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
