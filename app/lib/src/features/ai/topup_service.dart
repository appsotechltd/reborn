import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/ai_models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../gifts/gift_service.dart';
import '../gifts/gift_store.dart';

/// Buys Reborn AI unit packs through the app store and credits them on the
/// server. A purchase is consumed (Android) or finished (iOS) only after the
/// server accepted it; until then the store re-delivers it, and this service
/// sends it again. Units go to the signed-in account, so no other state is kept.
class TopUpService {
  TopUpService({required this.store, required this.repo, this.onCredited});

  final GiftStore store;
  final RebornRepository repo;

  /// Called after the server credits a pack.
  final void Function(AITopUp topUp)? onCredited;

  static bool isTopUpProduct(String productId) =>
      productId.startsWith('reborn.ai.');

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

  /// Buys [pack]. Throws [GiftCancelled], [GiftException] for store errors,
  /// or ApiException when the server rejects the purchase.
  Future<AITopUp> buy(UnitPack pack) async {
    if (store.platform == null) {
      throw const GiftException('Top-ups are coming soon in the app.');
    }
    start();
    final id = pack.productId;
    final completer = Completer<StorePurchase>();
    _waiting[id] = completer;
    try {
      if (!await store.buy(id)) {
        throw const GiftException("The store couldn't start the purchase.");
      }
      return await _deliver(await completer.future);
    } finally {
      if (identical(_waiting[id], completer)) _waiting.remove(id);
    }
  }

  void _onPurchases(List<StorePurchase> purchases) {
    for (final p in purchases) {
      if (!isTopUpProduct(p.productId)) continue;
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
            // Paid earlier but never confirmed: send it again.
            unawaited(_deliver(p).then((_) {}, onError: (Object _) {}));
          }
      }
    }
  }

  Future<AITopUp> _deliver(StorePurchase p) async {
    final topUp = switch (store.platform!) {
      GiftPlatform.apple => await repo.topUpApple(p.serverData),
      GiftPlatform.google => await repo.topUpGoogle(p.productId, p.serverData),
    };
    await store.finish(p);
    onCredited?.call(topUp);
    return topUp;
  }
}

/// Reborn AI's status for the signed-in member: rates, packs and wallet.
final aiStatusProvider = FutureProvider.autoDispose<AIStatus>((ref) {
  ref.watch(sessionProvider.select((s) => s.token));
  return ref.watch(repositoryProvider).aiStatus();
});

final topUpServiceProvider = Provider<TopUpService>((ref) {
  final service = TopUpService(
    store: ref.watch(giftStoreProvider),
    repo: ref.watch(repositoryProvider),
    onCredited: (_) => ref.invalidate(aiStatusProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
