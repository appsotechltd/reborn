import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/member_models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../gifts/gift_service.dart';
import '../gifts/gift_store.dart';

/// Buys a 30-day pass to a writer's subscriber cards through the app store
/// and records it on the server, the way gifts are bought.
///
/// The passes (`reborn.writer.month199|499|999`) are Play consumables and App
/// Store non-renewing subscriptions, so one member can hold passes to many
/// writers at the same price. Both are bought with [GiftStore.buy], which
/// calls the plugin's `buyConsumable`: on Android we consume the purchase
/// ourselves once the server accepts it (so the product can be bought again),
/// and on iOS the StoreKit 2 plugin buys every product type the same way;
/// a non-renewing subscription only needs finishing, which
/// [GiftStore.finish] does.
///
/// Until the server accepts it, the store re-delivers the purchase; [start]
/// listens for those and retries for the writer it was bought for.
class WriterPassService {
  WriterPassService({
    required this.store,
    required this.repo,
    required this.prefs,
    this.onSubscribed,
  });

  final GiftStore store;
  final RebornRepository repo;
  final SharedPreferences prefs;

  /// Called with the writer's handle after the server records a pass.
  final void Function(String handle)? onSubscribed;

  static const pendingPrefix = 'writerpass.pending.';

  static bool isPassProduct(String productId) =>
      productId.startsWith('reborn.writer.');

  StreamSubscription<List<StorePurchase>>? _sub;
  final _waiting = <String, Completer<StorePurchase>>{};

  void start() {
    if (_sub != null || store.platform == null) return;
    _sub = store.purchases.listen(_onPurchases, onError: (Object _) {});
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  /// Buys [tier]'s pass to [handle]. Throws [GiftCancelled] when the person
  /// backs out, [GiftException] for store errors and ApiException when the
  /// server rejects the purchase (which then stays unfinished).
  Future<WriterSubscription> subscribe(String handle, WriterTier tier) async {
    if (store.platform == null) {
      throw const GiftException('Subscriptions are coming soon in the app.');
    }
    start();
    final id = tier.productId;
    await prefs.setString('$pendingPrefix$id', handle);
    final completer = Completer<StorePurchase>();
    _waiting[id] = completer;
    try {
      if (!await store.buy(id)) {
        throw const GiftException("The store couldn't start the purchase.");
      }
      return await _deliver(handle, await completer.future);
    } finally {
      if (identical(_waiting[id], completer)) _waiting.remove(id);
    }
  }

  void _onPurchases(List<StorePurchase> purchases) {
    for (final p in purchases) {
      if (!isPassProduct(p.productId)) continue;
      final waiting = _waiting[p.productId];
      final open = waiting != null && !waiting.isCompleted;
      switch (p.status) {
        case StorePurchaseStatus.pending:
          break;
        case StorePurchaseStatus.canceled:
          if (open) waiting.completeError(const GiftCancelled());
        case StorePurchaseStatus.error:
          if (open) {
            waiting.completeError(
              GiftException(p.error ?? "The purchase didn't go through."),
            );
          }
        case StorePurchaseStatus.purchased:
        case StorePurchaseStatus.restored:
          if (open && p.status == StorePurchaseStatus.purchased) {
            waiting.complete(p);
          } else {
            unawaited(_recover(p));
          }
      }
    }
  }

  Future<WriterSubscription> _deliver(String handle, StorePurchase p) async {
    final sub = switch (store.platform!) {
      GiftPlatform.apple => await repo.subscribeApple(handle, p.serverData),
      GiftPlatform.google => await repo.subscribeGoogle(
        handle,
        p.productId,
        p.serverData,
      ),
    };
    await store.finish(p);
    await prefs.remove('$pendingPrefix${p.productId}');
    onSubscribed?.call(handle);
    return sub;
  }

  /// A paid pass nobody is waiting for: one that failed to reach the server
  /// earlier. Retry it for the writer it was bought for.
  Future<void> _recover(StorePurchase p) async {
    final handle = prefs.getString('$pendingPrefix${p.productId}');
    if (handle == null) return;
    try {
      await _deliver(handle, p);
    } catch (_) {
      // Left unfinished: the store delivers it again later.
    }
  }
}

final writerPassServiceProvider = Provider<WriterPassService>((ref) {
  final service = WriterPassService(
    store: ref.watch(giftStoreProvider),
    repo: ref.watch(repositoryProvider),
    prefs: ref.watch(sharedPreferencesProvider),
    onSubscribed: (handle) {
      ref.invalidate(writerOfferProvider(handle));
      ref.invalidate(mySubscriptionsProvider);
      ref.invalidate(userCardsProvider);
    },
  );
  ref.onDispose(service.dispose);
  return service;
});
