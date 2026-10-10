import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reborn/src/api/api_client.dart';
import 'package:reborn/src/data/offline_cache.dart';
import 'package:reborn/src/data/repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

/// A server that can be switched off to simulate losing the network.
class FakeServer {
  bool online = true;
  int status = 200;
  final routes = <String, Object>{};

  late final client = MockClient((req) async {
    if (!online) throw http.ClientException('Failed host lookup');
    if (status != 200) {
      return http.Response(
        jsonEncode({
          'error': {'code': 'internal', 'message': 'boom'},
        }),
        status,
      );
    }
    final body = routes[req.url.path];
    if (body == null) {
      return http.Response(
        jsonEncode({
          'error': {'code': 'not_found', 'message': 'nope'},
        }),
        404,
      );
    }
    return http.Response(jsonEncode(body), 200);
  });
}

void main() {
  late FakeServer server;
  late RebornRepository repo;
  late List<bool> connectivity;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    server = FakeServer();
    connectivity = [];
    repo = RebornRepository(
      ApiClient(httpClient: server.client, token: () => 'tok'),
      OfflineCache(prefs),
      onConnectivity: connectivity.add,
    );
  });

  test('feed falls back to the cached page when the network fails', () async {
    server.routes['/v1/feed'] = {
      'cards': [cardJson()],
      'next_cursor': 'next1',
    };
    final online = await repo.feed(topics: ['mindfulness']);
    expect(online.offline, isFalse);

    server.online = false;
    final offline = await repo.feed(topics: ['mindfulness']);
    expect(offline.offline, isTrue);
    expect(offline.value.cards.single.id, 'meditations-marcus-aurelius--01');
    expect(offline.value.nextCursor, 'next1');
    expect(connectivity, [false, true]);
  });

  test('daily idea is served from cache offline', () async {
    server.routes['/v1/daily'] = {'date': '2026-10-10', 'card': cardJson()};
    await repo.daily();
    server.online = false;
    final d = await repo.daily();
    expect(d.offline, isTrue);
    expect(d.value.date, '2026-10-10');
  });

  test('without a cached copy the network error is rethrown', () async {
    server.online = false;
    await expectLater(
      repo.daily(),
      throwsA(
        isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', true),
      ),
    );
  });

  test('server errors do not fall back to cache', () async {
    server.routes['/v1/daily'] = {'date': '2026-10-10', 'card': cardJson()};
    await repo.daily();
    server.status = 500;
    await expectLater(
      repo.daily(),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 's', 500)),
    );
  });

  test('stashed cards stay fully readable offline', () async {
    final health = healthCard().toJson();
    server.routes['/v1/stashes'] = {
      'stashes': [
        {
          'id': 's1',
          'name': 'Morning reads',
          'description': '',
          'card_count': 2,
          'created_at': '2026-10-10T12:00:00Z',
        },
      ],
    };
    server.routes['/v1/stashes/s1'] = {
      'stash': {
        'id': 's1',
        'name': 'Morning reads',
        'description': '',
        'card_count': 2,
        'created_at': '2026-10-10T12:00:00Z',
      },
      'cards': [cardJson(), health],
    };
    await repo.stashes();
    // Let the background prefetch of each stash finish.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    server.online = false;
    final list = await repo.stashes();
    expect(list.offline, isTrue);
    expect(list.value.single.name, 'Morning reads');

    final detail = await repo.stash('s1');
    expect(detail.offline, isTrue);
    expect(detail.value.cards.map((c) => c.id), [
      'meditations-marcus-aurelius--01',
      'nhs-sleep--01',
    ]);

    // Each stashed card opens on its own, with credit and disclaimer intact.
    final card = await repo.card('nhs-sleep--01');
    expect(card.offline, isTrue);
    expect(card.value.body, isNotEmpty);
    expect(card.value.credit, contains('NHS'));
    expect(card.value.disclaimer, healthDisclaimer);
  });

  test('an opened card is remembered for offline reading', () async {
    server.online = false;
    await repo.rememberCard(sampleCard({'id': 'x--01'}));
    final c = await repo.card('x--01');
    expect(c.offline, isTrue);
    expect(c.value.credit, startsWith('Source:'));
  });

  test(
    'topics fall back to the built-in list on first offline launch',
    () async {
      server.online = false;
      final t = await repo.topics();
      expect(t.offline, isTrue);
      expect(t.value, hasLength(12));
    },
  );
}
