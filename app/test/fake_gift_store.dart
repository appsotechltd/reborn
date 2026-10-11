import 'dart:async';

import 'package:reborn/src/features/gifts/gift_store.dart';

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

  /// (productId, userId) for each subscription started.
  final subscribed = <(String, String)>[];
  final finishedSubscriptions = <String>[];
  int restoreCalls = 0;

  @override
  Future<bool> subscribe(String productId, {required String userId}) async {
    subscribed.add((productId, userId));
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
  Future<void> finishSubscription(StorePurchase purchase) async =>
      finishedSubscriptions.add(purchase.productId);

  @override
  Future<void> restore() async => restoreCalls++;
}
