import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reborn/src/api/api_client.dart';
import 'package:reborn/src/api/models.dart';

import 'fixtures.dart';

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  group('error handling', () {
    test('parses the {"error":{code,message}} shape', () async {
      final api = ApiClient(
        baseUrl: 'http://api.test',
        httpClient: MockClient(
          (_) async => jsonResponse({
            'error': {'code': 'not_found', 'message': 'card not found'},
          }, 404),
        ),
      );
      await expectLater(
        api.card('missing'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.code, 'code', 'not_found')
              .having((e) => e.message, 'message', 'card not found')
              .having((e) => e.isNetwork, 'isNetwork', false),
        ),
      );
    });

    test('503 agent_unavailable and 429 are recognisable', () async {
      var status = 503;
      final api = ApiClient(
        httpClient: MockClient(
          (_) async => jsonResponse({
            'error': {
              'code': status == 503 ? 'agent_unavailable' : 'rate_limited',
              'message': 'nope',
            },
          }, status),
        ),
      );
      final msgs = [const ChatMessage(role: 'user', content: 'hi')];
      await expectLater(
        api.chat(msgs),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isAgentUnavailable,
            'agentUnavailable',
            true,
          ),
        ),
      );
      status = 429;
      await expectLater(
        api.chat(msgs),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isRateLimited,
            'rateLimited',
            true,
          ),
        ),
      );
    });

    test('non-JSON error body still yields an ApiException', () async {
      final api = ApiClient(
        httpClient: MockClient(
          (_) async => http.Response('<html>Bad gateway</html>', 502),
        ),
      );
      await expectLater(
        api.daily(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 502)
              .having((e) => e.code, 'code', 'http_502'),
        ),
      );
    });

    test('transport failures become network errors', () async {
      final api = ApiClient(
        httpClient: MockClient(
          (_) async => throw http.ClientException('connection refused'),
        ),
      );
      await expectLater(
        api.topics(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isNetwork, 'isNetwork', true)
              .having((e) => e.statusCode, 'statusCode', 0),
        ),
      );
    });

    test('401 is flagged as unauthorized', () async {
      final api = ApiClient(
        httpClient: MockClient(
          (_) async => jsonResponse({
            'error': {'code': 'unauthorized', 'message': 'sign in'},
          }, 401),
        ),
      );
      await expectLater(
        api.me(),
        throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'u', true)),
      );
    });
  });

  group('requests', () {
    test('sends bearer token and builds feed query', () async {
      late http.Request seen;
      final api = ApiClient(
        baseUrl: 'http://api.test/',
        token: () => 'tok123',
        httpClient: MockClient((req) async {
          seen = req;
          return jsonResponse({
            'cards': [cardJson()],
            'next_cursor': 'abc',
          });
        }),
      );
      final page = await api.feed(topics: ['money', 'health'], cursor: 'c1');
      expect(seen.method, 'GET');
      expect(seen.url.path, '/v1/feed');
      expect(seen.url.queryParameters, {
        'topics': 'money,health',
        'cursor': 'c1',
        'limit': '20',
      });
      expect(seen.headers['Authorization'], 'Bearer tok123');
      expect(page.cards.single.id, 'meditations-marcus-aurelius--01');
      expect(page.nextCursor, 'abc');
    });

    test('no Authorization header when signed out', () async {
      late http.Request seen;
      final api = ApiClient(
        httpClient: MockClient((req) async {
          seen = req;
          return jsonResponse({'date': '2026-10-10', 'card': cardJson()});
        }),
      );
      final daily = await api.daily();
      expect(seen.headers.containsKey('Authorization'), isFalse);
      expect(daily.date, '2026-10-10');
    });

    test('POST review sends grade and handles 204 endpoints', () async {
      final calls = <String>[];
      final api = ApiClient(
        token: () => 't',
        httpClient: MockClient((req) async {
          calls.add('${req.method} ${req.url.path} ${req.body}');
          if (req.url.path.startsWith('/v1/review/')) {
            return jsonResponse({
              'due_at': '2026-10-12T00:00:00Z',
              'interval_days': 2,
              'reps': 1,
            });
          }
          return http.Response('', 204);
        }),
      );
      final r = await api.review('meditations-marcus-aurelius--01', Grade.hard);
      expect(r.reps, 1);
      await api.addToStash('s1', 'c1');
      await api.recordView('c1');
      expect(calls, [
        'POST /v1/review/meditations-marcus-aurelius--01 {"grade":"hard"}',
        'PUT /v1/stashes/s1/cards/c1 ',
        'POST /v1/cards/c1/view ',
      ]);
    });

    test('chat sends the full history', () async {
      late Map<String, dynamic> body;
      final api = ApiClient(
        httpClient: MockClient((req) async {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return jsonResponse({
            'reply': 'See [meditations-marcus-aurelius--01].',
            'citations': [cardJson()],
          });
        }),
      );
      final reply = await api.chat(const [
        ChatMessage(role: 'user', content: 'a'),
        ChatMessage(role: 'assistant', content: 'b'),
        ChatMessage(role: 'user', content: 'c'),
      ]);
      expect(body['messages'], [
        {'role': 'user', 'content': 'a'},
        {'role': 'assistant', 'content': 'b'},
        {'role': 'user', 'content': 'c'},
      ]);
      expect(reply.citations.single.id, 'meditations-marcus-aurelius--01');
    });
  });
}
