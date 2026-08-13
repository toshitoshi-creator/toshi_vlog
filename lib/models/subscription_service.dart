import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:path_provider/path_provider.dart';

/// Tracks the app's single "premium" auto-renewable subscription.
///
/// There is no backend receipt validation here: entitlement is trusted from
/// the local StoreKit/Play Billing purchase stream and cached to disk so it
/// survives restarts. This is a common tradeoff for small/solo apps without
/// a server, but it means expiration is only re-checked when the store
/// actually reports it (e.g. via [restore] on launch), not continuously.
class SubscriptionService extends ChangeNotifier {
  static const productId = 'com.toshivlog.toshiVlog.premium_monthly';

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  bool _isAvailable = false;
  bool _isPremium = false;
  bool _purchasePending = false;
  String? _errorMessage;
  ProductDetails? _product;

  bool get isAvailable => _isAvailable;
  bool get isPremium => _isPremium;
  bool get purchasePending => _purchasePending;
  String? get errorMessage => _errorMessage;
  ProductDetails? get product => _product;

  Future<void> init() async {
    await _loadCachedEntitlement();

    _isAvailable = await _iap.isAvailable();
    notifyListeners();
    if (!_isAvailable) return;

    _subscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (_) {},
    );

    final response = await _iap.queryProductDetails({productId});
    if (response.productDetails.isNotEmpty) {
      _product = response.productDetails.first;
    } else {
      _errorMessage = '商品情報が見つかりませんでした';
    }
    notifyListeners();

    await _iap.restorePurchases();
  }

  Future<void> buy() async {
    final product = _product;
    if (product == null) return;
    _purchasePending = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
    } catch (_) {
      _purchasePending = false;
      _errorMessage = '購入を開始できませんでした';
      notifyListeners();
    }
  }

  Future<void> restore() async {
    _purchasePending = true;
    notifyListeners();
    await _iap.restorePurchases();
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID == productId) {
        switch (purchase.status) {
          case PurchaseStatus.pending:
            _purchasePending = true;
          case PurchaseStatus.purchased:
          case PurchaseStatus.restored:
            _purchasePending = false;
            await _setPremium(true);
          case PurchaseStatus.error:
            _purchasePending = false;
            _errorMessage = purchase.error?.message ?? '購入処理でエラーが発生しました';
          case PurchaseStatus.canceled:
            _purchasePending = false;
        }
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
    notifyListeners();
  }

  Future<File> _entitlementFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/entitlement.json');
  }

  Future<void> _loadCachedEntitlement() async {
    try {
      final file = await _entitlementFile();
      if (await file.exists()) {
        final raw =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _isPremium = raw['isPremium'] as bool? ?? false;
      }
    } catch (_) {
      _isPremium = false;
    }
  }

  Future<void> _setPremium(bool value) async {
    _isPremium = value;
    final file = await _entitlementFile();
    await file.writeAsString(jsonEncode({'isPremium': value}));
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
