import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plans.dart';

class Entitlement {
  const Entitlement({
    required this.isPro,
    this.expiresAt,
    this.productId,
    this.willRenew = false,
    this.preview = false,
    this.freeEdition = false,
  });

  static const free = Entitlement(isPro: false);

  final bool isPro;
  final DateTime? expiresAt;
  final String? productId;
  final bool willRenew;

  /// Granted by the local preview service — no real payment happened.
  final bool preview;

  /// Release build without a store configuration: every feature is unlocked
  /// and no purchase UI is shown, so the app is never half-finished (2.1).
  final bool freeEdition;
}

class PlanOffer {
  const PlanOffer({
    required this.plan,
    required this.priceLabel,
    this.introLabel,
    this.handle,
  });

  final PlanInfo plan;
  final String priceLabel;
  final String? introLabel;

  /// Store-specific object (RevenueCat [Package]).
  final Object? handle;
}

enum PurchaseOutcome { success, cancelled, failed, unavailable }

abstract class SubscriptionService {
  Entitlement get current;
  Stream<Entitlement> get changes;

  /// True when purchases do not reach a real store (development / web demo).
  bool get isPreview;

  /// Why purchasing is impossible right now, or null.
  String? get unavailableReason;

  /// False when the build has no store: hide every purchase-related UI.
  bool get storeEnabled;

  /// Where the user manages / cancels the subscription.
  Uri get managementUrl;

  Future<void> init();
  Future<List<PlanOffer>> offers();
  Future<PurchaseOutcome> purchase(PlanOffer offer);
  Future<Entitlement> restore();
}

/// Store pages where an auto-renewing subscription can be cancelled.
Uri platformManagementUrl() => defaultTargetPlatform == TargetPlatform.android
    ? Uri.parse('https://play.google.com/store/account/subscriptions')
    : Uri.parse('https://apps.apple.com/account/subscriptions');

// ── RevenueCat (production) ───────────────────────────────────────────────────

const _kRcAndroidKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY');
const _kRcIosKey = String.fromEnvironment('REVENUECAT_IOS_KEY');

String? revenueCatKeyForPlatform() {
  if (kIsWeb) return null;
  final key = switch (defaultTargetPlatform) {
    TargetPlatform.android => _kRcAndroidKey,
    TargetPlatform.iOS || TargetPlatform.macOS => _kRcIosKey,
    _ => '',
  };
  return key.isEmpty ? null : key;
}

class RevenueCatSubscriptionService implements SubscriptionService {
  RevenueCatSubscriptionService(this._apiKey);

  final String _apiKey;
  final _controller = StreamController<Entitlement>.broadcast();
  Entitlement _current = Entitlement.free;
  String? _error;

  @override
  Entitlement get current => _current;
  @override
  Stream<Entitlement> get changes => _controller.stream;
  @override
  bool get isPreview => false;
  @override
  String? get unavailableReason => _error;
  @override
  bool get storeEnabled => true;
  @override
  Uri get managementUrl => _managementUrl ?? platformManagementUrl();
  Uri? _managementUrl;

  void _apply(CustomerInfo info) {
    final url = info.managementURL;
    if (url != null) _managementUrl = Uri.tryParse(url);
    final e = info.entitlements.active[kEntitlementId];
    _current = e == null
        ? Entitlement.free
        : Entitlement(
            isPro: true,
            expiresAt: DateTime.tryParse(e.expirationDate ?? ''),
            productId: e.productIdentifier,
            willRenew: e.willRenew,
          );
    _controller.add(_current);
  }

  @override
  Future<void> init() async {
    try {
      await Purchases.configure(PurchasesConfiguration(_apiKey));
      Purchases.addCustomerInfoUpdateListener(_apply);
      _apply(await Purchases.getCustomerInfo());
    } on PlatformException catch (e) {
      _error = 'Mağaza bağlantısı kurulamadı (${e.code}).';
    }
  }

  @override
  Future<List<PlanOffer>> offers() async {
    try {
      final offering = (await Purchases.getOfferings()).current;
      if (offering == null) return const [];
      final out = <PlanOffer>[];
      for (final plan in kPlans) {
        final type = switch (plan.period) {
          PlanPeriod.weekly => PackageType.weekly,
          PlanPeriod.monthly => PackageType.monthly,
          PlanPeriod.yearly => PackageType.annual,
        };
        final pkg = offering.availablePackages
            .where((p) => p.packageType == type)
            .firstOrNull;
        if (pkg == null) continue;
        final intro = pkg.storeProduct.introductoryPrice;
        out.add(PlanOffer(
          plan: plan,
          priceLabel: pkg.storeProduct.priceString,
          introLabel: intro == null
              ? null
              : intro.price == 0
                  ? '${intro.periodNumberOfUnits} ${_unitTr(intro.periodUnit)} ücretsiz'
                  : 'İlk dönem ${intro.priceString}',
          handle: pkg,
        ));
      }
      return out;
    } on PlatformException catch (e) {
      _error = 'Paketler yüklenemedi (${e.code}).';
      return const [];
    }
  }

  @override
  Future<PurchaseOutcome> purchase(PlanOffer offer) async {
    final pkg = offer.handle;
    if (pkg is! Package) return PurchaseOutcome.unavailable;
    try {
      final result = await Purchases.purchase(PurchaseParams.package(pkg));
      _apply(result.customerInfo);
      return _current.isPro ? PurchaseOutcome.success : PurchaseOutcome.failed;
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      return code == PurchasesErrorCode.purchaseCancelledError
          ? PurchaseOutcome.cancelled
          : PurchaseOutcome.failed;
    }
  }

  @override
  Future<Entitlement> restore() async {
    try {
      _apply(await Purchases.restorePurchases());
    } on PlatformException catch (e) {
      _error = 'Geri yükleme başarısız (${e.code}).';
    }
    return _current;
  }

  static String _unitTr(PeriodUnit u) => switch (u) {
        PeriodUnit.day => 'gün',
        PeriodUnit.week => 'hafta',
        PeriodUnit.month => 'ay',
        PeriodUnit.year => 'yıl',
        _ => '',
      };
}

// ── Preview (no store configured) ─────────────────────────────────────────────

/// Local stand-in used in debug builds and the web demo. "Purchases" only set
/// a local expiry date; release builds without store keys disable buying.
class PreviewSubscriptionService implements SubscriptionService {
  PreviewSubscriptionService(this._prefs, {bool? allowPurchases})
      : _allowPurchases = allowPurchases ?? !kReleaseMode;

  static const _kExpiry = 'preview_pro_expiry';
  static const _kProduct = 'preview_pro_product';

  final SharedPreferences _prefs;
  final bool _allowPurchases;
  final _controller = StreamController<Entitlement>.broadcast();
  Entitlement _current = Entitlement.free;

  @override
  Entitlement get current => _current;
  @override
  Stream<Entitlement> get changes => _controller.stream;
  @override
  bool get isPreview => true;
  @override
  String? get unavailableReason => null;
  @override
  bool get storeEnabled => _allowPurchases;
  @override
  Uri get managementUrl => platformManagementUrl();

  void _load() {
    if (!_allowPurchases) {
      _current = const Entitlement(isPro: true, freeEdition: true);
      _controller.add(_current);
      return;
    }
    final exp = DateTime.tryParse(_prefs.getString(_kExpiry) ?? '');
    _current = exp != null && exp.isAfter(DateTime.now())
        ? Entitlement(
            isPro: true,
            expiresAt: exp,
            productId: _prefs.getString(_kProduct),
            preview: true,
          )
        : Entitlement.free;
    _controller.add(_current);
  }

  @override
  Future<void> init() async => _load();

  @override
  Future<List<PlanOffer>> offers() async => [
        for (final p in kPlans)
          PlanOffer(
            plan: p,
            priceLabel: p.fallbackPrice,
            introLabel: p.trialDays > 0 ? '${p.trialDays} gün ücretsiz' : null,
          ),
      ];

  @override
  Future<PurchaseOutcome> purchase(PlanOffer offer) async {
    if (!_allowPurchases) return PurchaseOutcome.unavailable;
    await _prefs.setString(
        _kExpiry, DateTime.now().add(offer.plan.duration).toIso8601String());
    await _prefs.setString(_kProduct, offer.plan.productId);
    _load();
    return PurchaseOutcome.success;
  }

  @override
  Future<Entitlement> restore() async {
    _load();
    return _current;
  }

  /// Developer helper: end the preview subscription.
  Future<void> reset() async {
    await _prefs.remove(_kExpiry);
    await _prefs.remove(_kProduct);
    _load();
  }
}
