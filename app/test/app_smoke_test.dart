import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reborn/src/app.dart';
import 'package:reborn/src/data/providers.dart';
import 'package:reborn/src/data/speaker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';
import 'fixtures.dart';

/// Full app against a fake HTTP server (real ApiClient, repository and cache).
void main() {
  late bool online;
  late List<String> requests;

  final client = MockClient((req) async {
    requests.add('${req.method} ${req.url.path}');
    if (!online) throw http.ClientException('offline');
    final body = switch (req.url.path) {
      '/v1/topics' => {
        'topics': [
          {
            'slug': 'mindfulness',
            'name': 'Mindfulness & Philosophy',
            'card_count': 1,
          },
          {'slug': 'health', 'name': 'Health & Wellness', 'card_count': 1},
        ],
      },
      '/v1/feed' => {
        'cards': [cardJson(), healthCard().toJson()],
        'next_cursor': null,
      },
      '/v1/timeline' => {
        'posts': [
          postJson(
            cardJson(),
            reason: {'kind': 'topic', 'label': 'Mindfulness & Philosophy'},
          ),
          postJson(healthCard().toJson()),
        ],
        'next_cursor': null,
      },
      '/v1/daily' => {'date': '2026-10-10', 'card': healthCard().toJson()},
      _ => null,
    };
    if (body == null) {
      return http.Response(
        jsonEncode({
          'error': {'code': 'not_found', 'message': 'not found'},
        }),
        404,
      );
    }
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  Future<void> pumpApp(
    WidgetTester tester,
    Map<String, Object> prefsValues,
  ) async {
    SharedPreferences.setMockInitialValues(prefsValues);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          httpClientProvider.overrideWithValue(client),
          speakerProvider.overrideWithValue(FakeSpeaker()),
        ],
        child: const RebornApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    online = true;
    requests = [];
  });

  testWidgets('first launch shows the topic picker, then the timeline', (
    tester,
  ) async {
    await pumpApp(tester, {});
    expect(find.text('Welcome to Reborn'), findsOneWidget);
    await tester.tap(find.text('Health & Wellness'));
    await tester.pump();
    await tester.tap(find.text('Continue with 1'));
    await tester.pumpAndSettle();
    expect(find.text("TODAY'S IDEA"), findsOneWidget);
    expect(find.text(sampleCard().title), findsOneWidget);
    expect(requests, contains('GET /v1/timeline'));
    // Signed out: a sign-up prompt, and nothing recorded as viewed or seen.
    expect(find.text('Make Reborn yours'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(requests.where((r) => r.endsWith('/view')), isEmpty);
    expect(requests, isNot(contains('POST /v1/seen')));
  });

  testWidgets('tabs work signed out and offline banner shows cached content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpApp(tester, {'onboarding.done': true});
    expect(find.text(sampleCard().title), findsOneWidget);
    expect(find.text('Offline — showing saved ideas'), findsNothing);

    await tester.tap(find.text('Ask'));
    await tester.pumpAndSettle();
    expect(find.text('Ask the library'), findsOneWidget);

    await tester.tap(find.text('Collections'));
    await tester.pumpAndSettle();
    expect(find.text('Keep the ideas you love'), findsOneWidget);

    // Lose the network and reload the feed: cached page + banner.
    online = false;
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Health & Wellness').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('For you'));
    await tester.pumpAndSettle();
    expect(find.text('Offline — showing saved ideas'), findsOneWidget);
    expect(find.text(sampleCard().title), findsOneWidget);

    // The daily idea opens from cache too, with its disclaimer.
    await tester.tap(find.text("TODAY'S IDEA"));
    await tester.pumpAndSettle();
    expect(find.text(healthDisclaimer), findsOneWidget);
    expect(find.text(healthCard().applyIt), findsOneWidget);
  });
}
