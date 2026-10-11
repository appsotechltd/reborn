import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import 'gift_store.dart';

/// The person closed the store's payment sheet.
class GiftCancelled implements Exception {
  const GiftCancelled();
}

class GiftException implements Exception {
  const GiftException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Buys a gift tier through the app store and records it on the server.
///
/// The purchase is finished (iOS) or consumed (Android) only after the server
/// accepted it. If that fails, the store keeps the purchase and re-delivers
/// it later; [start] listens for those and retries for the post it was for.
class GiftService {
  GiftService({required this.store, required this.repo, required this.prefs});

  final GiftStore store;
  final RebornRepository repo;
  final SharedPreferences prefs;

  static const pendingPrefix = 'gifts.pending.';

  StreamSubscription<List<StorePurchase>>? _sub;
  final _waiting = <String, Completer<StorePurchase>>{};

  /// Listens for purchase updates (call once at startup on mobile).
  void start() {
    if (_sub != null || store.platform == null) return;
    _sub = store.purchases.listen(_onPurchases, onError: (Object _) {});
    unawaited(store.restoreUnfinished());
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  /// Buys [tier] for [postId]. Throws [GiftCancelled] when the person backs
  /// out, [GiftException] for store errors and ApiException when the server
  /// rejects the purchase (which then stays unfinished).
  Future<Gift> give(String postId, GiftTier tier) async {
    if (store.platform == null) {
      throw const GiftException('Gifts are coming soon.');
    }
    start();
    final productId = tier.productId;
    await prefs.setString('$pendingPrefix$productId', postId);
    final completer = Completer<StorePurchase>();
    _waiting[productId] = completer;
    try {
      final started = await store.buy(productId);
      if (!started) {
        throw const GiftException("The store couldn't start the purchase.");
      }
      final purchase = await completer.future;
      return await _deliver(postId, purchase);
    } finally {
      if (identical(_waiting[productId], completer)) _waiting.remove(productId);
    }
  }

  void _onPurchases(List<StorePurchase> purchases) {
    for (final p in purchases) {
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

  Future<Gift> _deliver(String postId, StorePurchase p) async {
    final gift = switch (store.platform!) {
      GiftPlatform.apple => await repo.giftApple(postId, p.serverData),
      GiftPlatform.google => await repo.giftGoogle(
        postId,
        p.productId,
        p.serverData,
      ),
    };
    await store.finish(p);
    await prefs.remove('$pendingPrefix${p.productId}');
    return gift;
  }

  /// A paid purchase nobody is waiting for: one that failed to reach the
  /// server earlier. Retry it for the post it was bought for.
  Future<void> _recover(StorePurchase p) async {
    final postId = prefs.getString('$pendingPrefix${p.productId}');
    if (postId == null) return;
    try {
      await _deliver(postId, p);
    } catch (_) {
      // Left unfinished: the store delivers it again later.
    }
  }
}

final giftServiceProvider = Provider<GiftService>((ref) {
  final service = GiftService(
    store: ref.watch(giftStoreProvider),
    repo: ref.watch(repositoryProvider),
    prefs: ref.watch(sharedPreferencesProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
