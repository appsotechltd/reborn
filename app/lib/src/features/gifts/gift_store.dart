import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

/// The app store a build pays through.
enum GiftPlatform {
  apple('apple'),
  google('google');

  const GiftPlatform(this.provider);

  /// The key in GET /v1/gifts/tiers `providers`.
  final String provider;
}

enum StorePurchaseStatus { purchased, restored, pending, canceled, error }

/// A store purchase update, independent of the plugin's types.
class StorePurchase {
  const StorePurchase({
    required this.productId,
    required this.status,
    this.serverData = '',
    this.error,
    this.raw,
  });

  final String productId;
  final StorePurchaseStatus status;

  /// What the server verifies: on iOS (StoreKit 2) the signed transaction
  /// JWS, on Android the purchase token.
  final String serverData;
  final String? error;

  /// The plugin's [PurchaseDetails], needed to finish the purchase.
  final Object? raw;
}

/// In-app purchases: gift tiers (consumables) and Premium (subscriptions).
abstract class GiftStore {
  /// Null when this build has no store (web, desktop).
  GiftPlatform? get platform;

  Future<bool> isAvailable();

  /// Localized prices by product id, for the products the store knows.
  Future<Map<String, String>> prices(Set<String> productIds);

  Stream<List<StorePurchase>> get purchases;

  /// Starts a purchase; the result arrives on [purchases].
  Future<bool> buy(String productId);

  /// Finishes (iOS) or consumes (Android) a purchase. Call only after the
  /// server has accepted it.
  Future<void> finish(StorePurchase purchase);

  /// Re-delivers purchases that were paid for but never finished.
  Future<void> restoreUnfinished();

  /// Starts a subscription purchase tied to [userId] (iOS appAccountToken,
  /// Play obfuscatedAccountId); the result arrives on [purchases].
  Future<bool> subscribe(String productId, {required String userId});

  /// Completes a subscription purchase (iOS finish, Play acknowledge).
  /// Call only after the server has accepted it.
  Future<void> finishSubscription(StorePurchase purchase);

  /// Asks the store to re-deliver owned purchases ("Restore purchases").
  Future<void> restore();
}

/// Used where there is no store: gifts show as "coming soon".
class NoGiftStore implements GiftStore {
  const NoGiftStore();

  @override
  GiftPlatform? get platform => null;
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<Map<String, String>> prices(Set<String> productIds) async => const {};
  @override
  Stream<List<StorePurchase>> get purchases => const Stream.empty();
  @override
  Future<bool> buy(String productId) async => false;
  @override
  Future<void> finish(StorePurchase purchase) async {}
  @override
  Future<void> restoreUnfinished() async {}
  @override
  Future<bool> subscribe(String productId, {required String userId}) async =>
      false;
  @override
  Future<void> finishSubscription(StorePurchase purchase) async {}
  @override
  Future<void> restore() async {}
}

/// Apple / Google in-app purchases through the official `in_app_purchase`
/// plugin. On iOS it uses StoreKit 2 (the plugin's default since 0.4.x),
/// where `verificationData.serverVerificationData` is the transaction's
/// `jwsRepresentation`.
class IapGiftStore implements GiftStore {
  IapGiftStore(this.platform);

  @override
  final GiftPlatform platform;

  InAppPurchase get _iap => InAppPurchase.instance;
  final _products = <String, ProductDetails>{};

  @override
  Future<bool> isAvailable() async {
    try {
      return await _iap.isAvailable();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, String>> prices(Set<String> productIds) async {
    final missing = productIds.difference(_products.keys.toSet());
    if (missing.isNotEmpty) {
      final r = await _iap.queryProductDetails(missing);
      for (final p in r.productDetails) {
        _products[p.id] = p;
      }
    }
    return {
      for (final id in productIds)
        if (_products[id] != null) id: _products[id]!.price,
    };
  }

  @override
  Stream<List<StorePurchase>> get purchases =>
      _iap.purchaseStream.map((list) => list.map(_convert).toList());

  StorePurchase _convert(PurchaseDetails d) => StorePurchase(
    productId: d.productID,
    status: switch (d.status) {
      PurchaseStatus.purchased => StorePurchaseStatus.purchased,
      PurchaseStatus.restored => StorePurchaseStatus.restored,
      PurchaseStatus.pending => StorePurchaseStatus.pending,
      PurchaseStatus.canceled => StorePurchaseStatus.canceled,
      PurchaseStatus.error => StorePurchaseStatus.error,
    },
    serverData: d.verificationData.serverVerificationData,
    error: d.error?.message,
    raw: d,
  );

  @override
  Future<bool> buy(String productId) async {
    if (!_products.containsKey(productId)) await prices({productId});
    final product = _products[productId];
    if (product == null) return false;
    return _iap.buyConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
      // Android: consume ourselves once the server accepts the purchase.
      // iOS: consumables must use autoConsume; finishing is completePurchase.
      autoConsume: platform == GiftPlatform.apple,
    );
  }

  @override
  Future<void> finish(StorePurchase purchase) async {
    final d = purchase.raw;
    if (d is! PurchaseDetails) return;
    if (platform == GiftPlatform.google) {
      final android = _iap
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      // Consuming also acknowledges the purchase.
      await android.consumePurchase(d);
    } else if (d.pendingCompletePurchase) {
      await _iap.completePurchase(d);
    }
  }

  @override
  Future<void> restoreUnfinished() async {
    // StoreKit 2 re-delivers unfinished transactions by itself; Play needs
    // asking for purchases that were never consumed.
    if (platform == GiftPlatform.google) {
      try {
        await _iap.restorePurchases();
      } catch (_) {
        // Retried next launch.
      }
    }
  }

  @override
  Future<bool> subscribe(String productId, {required String userId}) async {
    if (!_products.containsKey(productId)) await prices({productId});
    final product = _products[productId];
    if (product == null) return false;
    // applicationUserName becomes the StoreKit 2 appAccountToken on iOS and
    // the obfuscatedAccountId on Play, so the server can match the owner.
    return _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(
        productDetails: product,
        applicationUserName: userId,
      ),
    );
  }

  @override
  Future<void> finishSubscription(StorePurchase purchase) async {
    final d = purchase.raw;
    if (d is PurchaseDetails && d.pendingCompletePurchase) {
      await _iap.completePurchase(d);
    }
  }

  @override
  Future<void> restore() => _iap.restorePurchases();
}

/// The store for this build: App Store on iOS, Play on Android, none on web.
GiftStore createGiftStore() {
  if (kIsWeb) return const NoGiftStore();
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS => IapGiftStore(GiftPlatform.apple),
    TargetPlatform.android => IapGiftStore(GiftPlatform.google),
    _ => const NoGiftStore(),
  };
}

final giftStoreProvider = Provider<GiftStore>((ref) => createGiftStore());
