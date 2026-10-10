import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reborn/src/api/api_client.dart';
import 'package:reborn/src/api/models.dart';
import 'package:reborn/src/data/offline_cache.dart';
import 'package:reborn/src/data/repository.dart';
import 'package:reborn/src/features/gifts/gift_service.dart';
import 'package:reborn/src/features/gifts/gift_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_server.dart';
import 'fixtures.dart';

/// A store whose purchases resolve to [outcome].
class FakeGiftStore implements GiftStore {
  FakeGiftStore(this.platform, {this.available = true});

  @override
  final GiftPlatform? platform;
  bool available;
  StorePurchaseStatus outcome = StorePurchaseStatus.purchased;
  final bought = <String>[];
  final finished = <String>[];
  final restored = <int>[];
  final _controller = StreamController<List<StorePurchase>>.broadcast();

  String get serverData =>
      platform == GiftPlatform.apple ? 'header.jws-payload.sig' : 'play-token';

  void deliver(StorePurchase p) => _controller.add([p]);

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<Map<String, String>> prices(Set<String> ids) async => {
    for (final id in ids) id: '£${ids.toList().indexOf(id) + 1}.99',
  };

  @override
  Stream<List<StorePurchase>> get purchases => _controller.stream;

  @override
  Future<bool> buy(String productId) async {
    bought.add(productId);
    scheduleMicrotask(
      () => deliver(
        StorePurchase(
          productId: productId,
          status: outcome,
          serverData: serverData,
          error: outcome == StorePurchaseStatus.error ? 'Card declined' : null,
        ),
      ),
    );
    return true;
  }

  @override
  Future<void> finish(StorePurchase purchase) async =>
      finished.add(purchase.productId);

  @override
  Future<void> restoreUnfinished() async => restored.add(1);
}

const lamp = GiftTier(
  id: 'lamp',
  name: 'Lamp',
  amountCents: 499,
  currency: 'usd',
  productId: 'reborn.gift.lamp',
);

Map<String, dynamic> giftJson(String provider) => {
  'id': 'g1',
  'post_id': 'p1',
  'tier': 'lamp',
  'amount_cents': 499,
  'currency': 'usd',
  'provider': provider,
  'status': 'paid',
  'created_at': '2026-10-10T09:00:00Z',
  'paid_at': '2026-10-10T09:00:00Z',
};

void main() {
  late FakeServer server;
  late SharedPreferences prefs;

  Future<GiftService> service(FakeGiftStore store) async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    final repo = RebornRepository(
      ApiClient(httpClient: server.client, token: () => 't'),
      OfflineCache(prefs),
    );
    return GiftService(store: store, repo: repo, prefs: prefs);
  }

  setUp(() {
    server = FakeServer()
      ..on(
        'POST /v1/posts/p1/gifts/apple',
        (_) => Reply(giftJson('apple'), 201),
      )
      ..on(
        'POST /v1/posts/p1/gifts/google',
        (_) => Reply(giftJson('google'), 201),
      );
  });

  test(
    'iOS: sends the StoreKit 2 JWS, then finishes the transaction',
    () async {
      final store = FakeGiftStore(GiftPlatform.apple);
      final s = await service(store);
      final gift = await s.give('p1', lamp);
      expect(gift.provider, 'apple');
      expect(store.bought, ['reborn.gift.lamp']);
      expect(server.called('POST /v1/posts/p1/gifts/apple').single.body, {
        'signed_transaction': 'header.jws-payload.sig',
      });
      expect(store.finished, ['reborn.gift.lamp']);
      expect(
        prefs.getString('${GiftService.pendingPrefix}reborn.gift.lamp'),
        isNull,
      );
      s.dispose();
    },
  );

  test('Android: sends product id and purchase token, then consumes', () async {
    final store = FakeGiftStore(GiftPlatform.google);
    final s = await service(store);
    await s.give('p1', lamp);
    expect(server.called('POST /v1/posts/p1/gifts/google').single.body, {
      'product_id': 'reborn.gift.lamp',
      'purchase_token': 'play-token',
    });
    expect(store.finished, ['reborn.gift.lamp']);
    expect(store.restored, [1]); // asks Play for unconsumed purchases
    s.dispose();
  });

  test(
    'a purchase the server rejects is not finished, and is retried',
    () async {
      server.on(
        'POST /v1/posts/p1/gifts/apple',
        (_) => Reply.error(502, 'payment_error', "couldn't check the purchase"),
      );
      final store = FakeGiftStore(GiftPlatform.apple);
      final s = await service(store);
      await expectLater(
        s.give('p1', lamp),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'payment_error'),
        ),
      );
      expect(store.finished, isEmpty);
      expect(
        prefs.getString('${GiftService.pendingPrefix}reborn.gift.lamp'),
        'p1',
      );

      // Later the store re-delivers it; this time the server accepts.
      server.on(
        'POST /v1/posts/p1/gifts/apple',
        (_) => Reply(giftJson('apple'), 201),
      );
      store.deliver(
        StorePurchase(
          productId: 'reborn.gift.lamp',
          status: StorePurchaseStatus.purchased,
          serverData: store.serverData,
        ),
      );
      await pumpEventQueue();
      expect(store.finished, ['reborn.gift.lamp']);
      s.dispose();
    },
  );

  test('cancel and store errors', () async {
    final store = FakeGiftStore(GiftPlatform.google)
      ..outcome = StorePurchaseStatus.canceled;
    final s = await service(store);
    await expectLater(s.give('p1', lamp), throwsA(isA<GiftCancelled>()));
    store.outcome = StorePurchaseStatus.error;
    await expectLater(
      s.give('p1', lamp),
      throwsA(
        isA<GiftException>().having((e) => e.message, 'm', 'Card declined'),
      ),
    );
    expect(server.calls, isEmpty);
    expect(store.finished, isEmpty);
    s.dispose();
  });

  group('gift sheet', () {
    void tiers(FakeServer s, {required bool apple, required bool google}) => s
      ..on(
        'GET /v1/gifts/tiers',
        (_) => {
          'tiers': [
            {
              'id': 'spark',
              'name': 'Spark',
              'amount_cents': 199,
              'currency': 'usd',
              'product_id': 'reborn.gift.spark',
            },
            {
              'id': 'lamp',
              'name': 'Lamp',
              'amount_cents': 499,
              'currency': 'usd',
              'product_id': 'reborn.gift.lamp',
            },
          ],
          'providers': {'stripe': false, 'apple': apple, 'google': google},
        },
      )
      ..on(
        'GET /v1/posts/${sampleCard().id}',
        (_) => postJson(
          cardJson(),
          viewer: {'reaction': null, 'favorited': false, 'seen': true},
        ),
      )
      ..on(
        'POST /v1/posts/${sampleCard().id}/gifts/google',
        (_) => Reply(giftJson('google'), 201),
      );

    testWidgets('buys through the store and thanks the giver', (tester) async {
      final s = FakeServer();
      tiers(s, apple: false, google: true);
      final store = FakeGiftStore(GiftPlatform.google);
      await pumpApp(
        tester,
        s,
        prefs: signedInPrefs,
        location: '/cards/${sampleCard().id}',
        giftStore: store,
      );
      await tester.tap(find.byKey(const ValueKey('post-gift')));
      await tester.pumpAndSettle();
      expect(find.text('Gifts are coming soon'), findsNothing);
      expect(find.text('£2.99'), findsOneWidget); // store's localized price
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('gift-tier-lamp')),
          matching: find.text('Gift'),
        ),
      );
      await tester.pumpAndSettle();
      expect(store.bought, ['reborn.gift.lamp']);
      expect(store.finished, ['reborn.gift.lamp']);
      expect(
        find.text('Thank you! Your Lamp gift supports Reborn.'),
        findsOneWidget,
      );
      expect(find.text('Gift · 1'), findsOneWidget);
    });

    testWidgets('provider off for this platform: coming soon', (tester) async {
      final s = FakeServer();
      tiers(s, apple: true, google: false);
      final store = FakeGiftStore(GiftPlatform.google);
      await pumpApp(
        tester,
        s,
        prefs: signedInPrefs,
        location: '/cards/${sampleCard().id}',
        giftStore: store,
      );
      await tester.tap(find.byKey(const ValueKey('post-gift')));
      await tester.pumpAndSettle();
      expect(find.text('Gifts are coming soon'), findsOneWidget);
      expect(find.text(r'$4.99'), findsOneWidget);
      expect(store.bought, isEmpty);
    });

    testWidgets('store unavailable: coming soon', (tester) async {
      final s = FakeServer();
      tiers(s, apple: true, google: true);
      await pumpApp(
        tester,
        s,
        prefs: signedInPrefs,
        location: '/cards/${sampleCard().id}',
        giftStore: FakeGiftStore(GiftPlatform.apple, available: false),
      );
      await tester.tap(find.byKey(const ValueKey('post-gift')));
      await tester.pumpAndSettle();
      expect(find.text('Gifts are coming soon'), findsOneWidget);
    });
  });
}
