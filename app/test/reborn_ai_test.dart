import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reborn/src/api/ai_models.dart';
import 'package:reborn/src/api/api_client.dart';
import 'package:reborn/src/data/offline_cache.dart';
import 'package:reborn/src/data/repository.dart';
import 'package:reborn/src/features/ai/ai_chart.dart';
import 'package:reborn/src/features/ai/topup_service.dart';
import 'package:reborn/src/features/ai/voice_recorder.dart';
import 'package:reborn/src/features/gifts/gift_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_gift_store.dart';
import 'fake_server.dart';
import 'fixtures.dart';

Map<String, Object?> wallet({int left = 240, int topup = 0}) => {
  'monthly_units': 250,
  'allowance_used': 250 - left,
  'allowance_left': left,
  'topup_units': topup,
  'remaining': left + topup,
  'resets_at': '2026-11-01T00:00:00Z',
};

Map<String, Object?> status({bool premium = true, bool available = true}) => {
  'available': available,
  'premium': premium,
  'wallet': premium ? wallet() : null,
  'rates': [
    {'kind': 'text', 'units': 1, 'per': 'reply'},
    {'kind': 'chart', 'units': 1, 'per': 'chart'},
    {'kind': 'voice', 'units': 1, 'per': '30 words'},
    {'kind': 'picture', 'units': 12, 'per': 'image'},
  ],
  'packs': [
    {
      'id': 'units_250',
      'name': 'Small top-up',
      'units': 250,
      'amount_cents': 299,
      'currency': 'usd',
      'product_id': 'reborn.ai.units250',
    },
  ],
  'providers': {'stripe': true, 'apple': true, 'google': true},
};

void main() {
  group('models', () {
    test('wallet summary and reset date', () {
      final w = AIWallet.fromJson(wallet(left: 40, topup: 600));
      expect(
        w.summary,
        '40 of 250 units left this month, plus 600 units from top-ups',
      );
      expect(w.resetLabel, 'Resets 1 Nov');
      expect(w.allowanceShare, closeTo(0.16, 0.001));
      expect(unitsLabel(1), '1 unit');
      expect(unitsLabel(1300), '1,300 units');
    });

    test('chart description reads every value', () {
      final c = AIChartData.fromJson({
        'kind': 'bar',
        'title': 'Focus',
        'unit': 'hours',
        'labels': ['Mon', 'Tue'],
        'series': [
          {
            'name': 'Hours',
            'values': [2, 3.5],
          },
        ],
      });
      expect(c.description, 'Focus: Mon 2, Tue 3.5 (hours)');
    });

    test('wavFromPcm16 writes a 44-byte header', () {
      final wav = wavFromPcm16(Uint8List(32000), sampleRate: 16000);
      expect(wav.length, 44 + 32000);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      final b = ByteData.sublistView(wav);
      expect(b.getUint32(24, Endian.little), 16000);
      expect(b.getUint32(40, Endian.little), 32000);
    });
  });

  group('TopUpService', () {
    late FakeServer server;

    Future<TopUpService> service(FakeGiftStore store, List<AITopUp> got) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = RebornRepository(
        ApiClient(httpClient: server.client, token: () => 't'),
        OfflineCache(prefs),
      );
      return TopUpService(store: store, repo: repo, onCredited: got.add);
    }

    const pack = UnitPack(
      id: 'units_250',
      name: 'Small top-up',
      units: 250,
      amountCents: 299,
      currency: 'usd',
      productId: 'reborn.ai.units250',
    );
    final paid = {'id': 'tu1', 'units': 250, 'status': 'paid'};

    setUp(() {
      server = FakeServer()
        ..on('POST /v1/ai/topups/apple', (_) => Reply(paid, 201))
        ..on('POST /v1/ai/topups/google', (_) => Reply(paid, 201));
    });

    test('iOS: credits on the server, then finishes', () async {
      final store = FakeGiftStore(GiftPlatform.apple);
      final got = <AITopUp>[];
      final s = await service(store, got);
      final t = await s.buy(pack);
      expect(t.units, 250);
      expect(server.called('POST /v1/ai/topups/apple').single.body, {
        'signed_transaction': 'header.jws-payload.sig',
      });
      expect(store.finished, ['reborn.ai.units250']);
      expect(got.single.id, 'tu1');
      s.dispose();
    });

    test('Android: sends the purchase token', () async {
      final store = FakeGiftStore(GiftPlatform.google);
      final s = await service(store, []);
      await s.buy(pack);
      expect(server.called('POST /v1/ai/topups/google').single.body, {
        'product_id': 'reborn.ai.units250',
        'purchase_token': 'play-token',
      });
      s.dispose();
    });

    test('an unfinished purchase is sent again', () async {
      final store = FakeGiftStore(GiftPlatform.google);
      final s = await service(store, []);
      s.start();
      store.deliver(
        const StorePurchase(
          productId: 'reborn.ai.units600',
          status: StorePurchaseStatus.purchased,
          serverData: 'old-token',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(server.called('POST /v1/ai/topups/google'), hasLength(1));
      expect(store.finished, ['reborn.ai.units600']);
      s.dispose();
    });

    test('a server rejection leaves the purchase unfinished', () async {
      server.on(
        'POST /v1/ai/topups/apple',
        (_) => Reply.error(400, 'invalid_purchase', 'bad receipt'),
      );
      final store = FakeGiftStore(GiftPlatform.apple);
      final s = await service(store, []);
      await expectLater(s.buy(pack), throwsA(isA<ApiException>()));
      expect(store.finished, isEmpty);
      s.dispose();
    });
  });

  group('screen', () {
    testWidgets('signed out asks to sign in', (tester) async {
      final server = FakeServer()..on('GET /v1/ai', (_) => status());
      await pumpApp(tester, server, location: '/ai');
      expect(
        find.text(
          'Sign in to chat with Reborn AI by text or voice. It answers from the library and can draw charts and pictures.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('free members see the Premium upsell', (tester) async {
      final server = FakeServer()
        ..on('GET /v1/ai', (_) => status(premium: false));
      await pumpApp(tester, server, prefs: signedInPrefs, location: '/ai');
      expect(find.text('Get Premium'), findsOneWidget);
      expect(find.text('What things cost'), findsOneWidget);
      expect(find.text('12 units'), findsOneWidget);
    });

    testWidgets('chats, shows the chart and the new balance', (tester) async {
      final server = FakeServer()
        ..on('GET /v1/ai', (_) => status())
        ..on(
          'POST /v1/ai/chat',
          (call) => {
            'conversation': {'id': 'c1', 'title': 'Focus'},
            'user_message': {
              'id': 'm1',
              'role': 'user',
              'content': call.body['message'],
            },
            'message': {
              'id': 'm2',
              'role': 'assistant',
              'content': 'Here is your week.',
              'units': 2,
              'attachments': [
                {
                  'type': 'chart',
                  'chart': {
                    'kind': 'bar',
                    'title': 'Focus hours',
                    'unit': 'hours',
                    'labels': ['Mon', 'Tue'],
                    'series': [
                      {
                        'name': 'Hours',
                        'values': [2, 4],
                      },
                    ],
                  },
                },
              ],
            },
            'wallet': wallet(left: 238),
          },
        );
      await pumpApp(tester, server, prefs: signedInPrefs, location: '/ai');
      expect(find.text('240 units left'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Chart my focus');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(server.called('POST /v1/ai/chat').single.body, {
        'message': 'Chart my focus',
      });
      expect(find.text('Chart my focus'), findsOneWidget);
      expect(find.text('Here is your week.'), findsOneWidget);
      expect(find.byType(AIChart), findsOneWidget);
      expect(find.text('Focus hours'), findsOneWidget);
      expect(find.text('238 units left'), findsOneWidget);
      expect(find.text('2 units'), findsOneWidget);
    });

    testWidgets('out of units offers a top-up', (tester) async {
      final server = FakeServer()
        ..on('GET /v1/ai', (_) => status())
        ..on(
          'POST /v1/ai/chat',
          (_) => Reply.error(402, 'out_of_units', 'no units left'),
        );
      await pumpApp(tester, server, prefs: signedInPrefs, location: '/ai');
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining("You've used all your AI units"),
        findsOneWidget,
      );
      // The message comes back so nothing typed is lost.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Hello',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Top up').last);
      await tester.pumpAndSettle();
      expect(find.text('Top up AI units'), findsOneWidget);
      expect(find.text('250 units'), findsOneWidget);
    });

    testWidgets('top-up sheet buys a pack in the store', (tester) async {
      final store = FakeGiftStore(GiftPlatform.google);
      final server = FakeServer()
        ..on('GET /v1/ai', (_) => status())
        ..on(
          'POST /v1/ai/topups/google',
          (_) => Reply({'id': 'tu1', 'units': 250, 'status': 'paid'}, 201),
        );
      await pumpApp(
        tester,
        server,
        prefs: signedInPrefs,
        location: '/ai',
        giftStore: store,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Top up'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '£1.99'));
      await tester.pumpAndSettle();
      expect(store.bought, ['reborn.ai.units250']);
      expect(store.finished, ['reborn.ai.units250']);
      expect(find.text('Added 250 units.'), findsOneWidget);
    });
  });
}
