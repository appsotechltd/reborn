import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reborn/src/data/providers.dart';
import 'package:reborn/src/features/ask/ask_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';

void main() {
  late int status;
  late List<Map<String, dynamic>> bodies;

  Future<ProviderContainer> container() async {
    SharedPreferences.setMockInitialValues({'auth.token': 'tok'});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        httpClientProvider.overrideWithValue(
          MockClient((req) async {
            expect(req.headers['Authorization'], 'Bearer tok');
            bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
            if (status == 200) {
              return http.Response(
                jsonEncode({
                  'reply': 'Expect friction [meditations-marcus-aurelius--01].',
                  'citations': [cardJson()],
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                'error': {
                  'code': status == 503 ? 'agent_unavailable' : 'rate_limited',
                  'message': 'x',
                },
              }),
              status,
            );
          }),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    status = 200;
    bodies = [];
  });

  test('sends full history and stores reply with citations', () async {
    final c = await container();
    final ask = c.read(askProvider.notifier);
    expect(await ask.send('first'), isNull);
    expect(await ask.send('second'), isNull);
    expect(bodies.last['messages'], [
      {'role': 'user', 'content': 'first'},
      {
        'role': 'assistant',
        'content': 'Expect friction [meditations-marcus-aurelius--01].',
      },
      {'role': 'user', 'content': 'second'},
    ]);
    final state = c.read(askProvider);
    expect(state.entries, hasLength(4));
    expect(
      state.entries.last.citations.single.id,
      'meditations-marcus-aurelius--01',
    );
  });

  test(
    '503 agent_unavailable is explained and the question restored',
    () async {
      status = 503;
      final c = await container();
      final restored = await c.read(askProvider.notifier).send('hello');
      expect(restored, 'hello');
      final state = c.read(askProvider);
      expect(state.entries, isEmpty);
      expect(state.error, contains('unavailable'));
    },
  );

  test('429 explains the hourly limit', () async {
    status = 429;
    final c = await container();
    await c.read(askProvider.notifier).send('hello');
    expect(c.read(askProvider).error, contains('limit'));
  });
}
