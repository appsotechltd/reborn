import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reborn/src/app.dart';
import 'package:reborn/src/data/device_timezone.dart';
import 'package:reborn/src/data/providers.dart';
import 'package:reborn/src/data/speaker.dart';
import 'package:reborn/src/features/gifts/gift_store.dart';
import 'package:reborn/src/features/notifications/push_service.dart';
import 'package:reborn/src/features/post/share.dart';
import 'package:reborn/src/router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// A recorded request.
class Call {
  Call(this.method, this.path, this.query, this.body);
  final String method;
  final String path;
  final Map<String, String> query;
  final dynamic body;

  @override
  String toString() => '$method $path';
}

/// A reply from a [FakeServer] handler.
class Reply {
  const Reply(this.body, [this.status = 200]);
  const Reply.empty([this.status = 204]) : body = null;
  Reply.error(this.status, String code, String message)
    : body = {
        'error': {'code': code, 'message': message},
      };
  final Object? body;
  final int status;
}

/// In-memory API: handlers keyed by "METHOD /path" (exact) return a body
/// (Map/List, sent as 200) or a [Reply]. Unknown routes are 404.
class FakeServer {
  final routes = <String, Object? Function(Call call)>{};
  final calls = <Call>[];

  void on(String route, Object? Function(Call call) handler) =>
      routes[route] = handler;

  List<String> get log => calls.map((c) => c.toString()).toList();
  Iterable<Call> called(String route) =>
      calls.where((c) => c.toString() == route);

  late final http.Client client = MockClient((req) async {
    final call = Call(
      req.method,
      req.url.path,
      req.url.queryParameters,
      req.body.isEmpty ? null : jsonDecode(req.body),
    );
    calls.add(call);
    final handler = routes['${req.method} ${req.url.path}'];
    final out = handler?.call(call);
    final reply = out is Reply
        ? out
        : (handler == null
              ? Reply.error(404, 'not_found', 'not found')
              : Reply(out));
    if (reply.body == null) return http.Response('', reply.status);
    return http.Response(
      jsonEncode(reply.body),
      reply.status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

class FakeSharer implements Sharer {
  final shared = <String>[];
  bool result = true;

  @override
  Future<bool> share({
    required String text,
    required String subject,
    Rect? origin,
  }) async {
    shared.add(text);
    return result;
  }
}

/// Pumps the whole app against [server], starting at [location].
Future<ProviderContainer> pumpApp(
  WidgetTester tester,
  FakeServer server, {
  Map<String, Object> prefs = const {'onboarding.done': true},
  String? location,
  Sharer? sharer,
  GiftStore? giftStore,
  PushMessaging? push,
  String? timezone,
  Size size = const Size(800, 2000),
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  server.routes.putIfAbsent(
    'GET /v1/topics',
    () =>
        (_) => {'topics': <Object>[]},
  );
  server.routes.putIfAbsent(
    'GET /v1/daily',
    () =>
        (_) => Reply.error(404, 'not_found', 'none'),
  );
  server.routes.putIfAbsent(
    'GET /v1/timeline',
    () =>
        (_) => {'posts': <Object>[], 'next_cursor': null},
  );
  final defaults = <String, Object? Function(Call)>{
    'GET /v1/notifications': (_) => {'notifications': <Object>[], 'unread': 0},
    'GET /v1/me/streak': (_) => {
      'current': 0,
      'longest': 0,
      'today': 0,
      'goal': 3,
      'last_days': <Object>[],
    },
    'GET /v1/me/blocks': (_) => {'blocks': <Object>[]},
    'GET /v1/discover': (_) => <String, Object>{},
  };
  defaults.forEach((k, v) => server.routes.putIfAbsent(k, () => v));
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        httpClientProvider.overrideWithValue(server.client),
        speakerProvider.overrideWithValue(FakeSpeaker()),
        sharerProvider.overrideWithValue(sharer ?? FakeSharer()),
        giftStoreProvider.overrideWithValue(giftStore ?? const NoGiftStore()),
        pushMessagingProvider.overrideWithValue(push),
        deviceTimezoneProvider.overrideWithValue(() async => timezone),
        ...overrides,
      ],
      child: const RebornApp(),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(RebornApp)),
  );
  if (location != null) {
    container.read(routerProvider).push(location);
  }
  await tester.pumpAndSettle();
  return container;
}

/// Pushes [location] on the app's router.
Future<void> push(
  WidgetTester tester,
  ProviderContainer container,
  String location, {
  Object? extra,
}) async {
  container.read(routerProvider).push(location, extra: extra);
  await tester.pumpAndSettle();
}

String currentPath(ProviderContainer c) =>
    c.read(routerProvider).routerDelegate.currentConfiguration.uri.path;
