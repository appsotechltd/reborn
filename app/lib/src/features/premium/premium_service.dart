import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../gifts/gift_service.dart';
import '../gifts/gift_store.dart';

/// Subscribes to Premium through the app store and confirms it with the
/// server. A purchase is completed only after the server accepts it; purchases
/// the store re-delivers (including "Restore purchases") are sent again.
class PremiumService {
  PremiumService({
    required this.store,
    required this.repo,
    this.onStatus,
    this.onError,
  });

  final GiftStore store;
  final RebornRepository repo;

  /// Called with the server's premium status after a purchase is confirmed.
  final void Function(PremiumStatus status)? onStatus;

  /// Called when a re-delivered or restored purchase is rejected.
  final void Function(Object error)? onError;

  static bool isPremiumProduct(String productId) =>
      productId.startsWith('reborn.premium.');

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

  /// Buys [plan] for [userId]. Throws [GiftCancelled], [GiftException] for
  /// store errors, or ApiException when the server rejects it (for example
  /// `409 subscription_taken`).
  Future<PremiumStatus> subscribe(PremiumPlan plan, String userId) async {
    if (store.platform == null) {
      throw const GiftException('Premium is coming soon.');
    }
    start();
    final id = plan.productId;
    final completer = Completer<StorePurchase>();
    _waiting[id] = completer;
    try {
      if (!await store.subscribe(id, userId: userId)) {
        throw const GiftException("The store couldn't start the purchase.");
      }
      return await _deliver(await completer.future);
    } finally {
      if (identical(_waiting[id], completer)) _waiting.remove(id);
    }
  }

  /// Asks the store for owned subscriptions; they arrive as restored
  /// purchases and are confirmed with the server.
  Future<void> restore() async {
    start();
    await store.restore();
  }

  void _onPurchases(List<StorePurchase> purchases) {
    for (final p in purchases) {
      if (!isPremiumProduct(p.productId)) continue;
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
            unawaited(
              _deliver(p).then((_) {}, onError: (Object e) => onError?.call(e)),
            );
          }
      }
    }
  }

  Future<PremiumStatus> _deliver(StorePurchase p) async {
    final status = switch (store.platform!) {
      GiftPlatform.apple => await repo.premiumApple(p.serverData),
      GiftPlatform.google => await repo.premiumGoogle(
        p.productId,
        p.serverData,
      ),
    };
    await store.finishSubscription(p);
    onStatus?.call(status);
    return status;
  }
}

/// The last error from a restored purchase, shown on the Premium screen.
class PremiumError extends Notifier<Object?> {
  @override
  Object? build() => null;

  void set(Object? e) => state = e;
}

final premiumErrorProvider = NotifierProvider<PremiumError, Object?>(
  PremiumError.new,
);

final premiumServiceProvider = Provider<PremiumService>((ref) {
  final service = PremiumService(
    store: ref.watch(giftStoreProvider),
    repo: ref.watch(repositoryProvider),
    onStatus: (_) {
      ref.read(premiumErrorProvider.notifier).set(null);
      ref.invalidate(premiumProvider);
      ref.read(sessionProvider.notifier).refreshUser();
    },
    onError: (e) => ref.read(premiumErrorProvider.notifier).set(e),
  );
  ref.onDispose(service.dispose);
  return service;
});
