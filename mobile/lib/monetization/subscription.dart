import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'plans.dart';

class Entitlement {
  const Entitlement({
    required this.isPro,
    this.expiresAt,
    this.productId,
    this.willRenew = false,
    this.preview = false,
    this.freeEdition = false,
    this.offlineCache = false,
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

  /// The store could not be reached; Pro comes from the last confirmed
  /// subscription period stored on the device (tournament halls are offline).
  final bool offlineCache;
}

class PlanOffer {
  const PlanOffer({
    required this.plan,
    required this.priceLabel,
    this.introLabel,
    this.perWeekLabel,
    this.amount,
    this.handle,
  });

  final PlanInfo plan;

  /// The billed amount, localized by the store ("₺79,99"). Always the most
  /// prominent price on the paywall (App Store 3.1.2).
  final String priceLabel;

  /// Free trial / intro offer, only when the user is eligible for it.
  final String? introLabel;

  /// Secondary comparison price for longer plans ("₺13,46 / hafta").
  final String? perWeekLabel;

  /// Numeric price in the store currency (for savings badges only).
  final double? amount;

  /// Store-specific object (RevenueCat [Package]).
  final Object? handle;

  /// Price of one week on this plan, in the store currency.
  double? get weeklyAmount =>
      amount == null ? null : amount! / plan.duration.inDays * 7;
}

/// Whole-percent saving of [offer] against the weekly plan, or null.
int? savingVsWeekly(PlanOffer offer, List<PlanOffer> all) {
  if (offer.plan.period == PlanPeriod.weekly) return null;
  final weekly = all.where((o) => o.plan.period == PlanPeriod.weekly).firstOrNull;
  final base = weekly?.amount;
  final mine = offer.weeklyAmount;
  if (base == null || mine == null || base <= 0) return null;
  final pct = ((1 - mine / base) * 100).floor();
  return pct >= 10 ? pct : null;
}

/// What the paywall shows. Copy and the preselected plan can be changed
/// remotely through RevenueCat offering metadata (and A/B tested with
/// RevenueCat Experiments) without an app update.
class PaywallConfig {
  const PaywallConfig({
    required this.offers,
    this.defaultPeriod,
    this.headline,
    this.subheadline,
  });

  final List<PlanOffer> offers;
  final PlanPeriod? defaultPeriod;
  final String? headline;
  final String? subheadline;
}

/// Offering metadata keys (RevenueCat dashboard → Offering → Metadata).
abstract final class PaywallMetadataKey {
  static const defaultPlan = 'default_plan'; // weekly | monthly | yearly
  static const headline = 'headline';
  static const subheadline = 'subheadline';
}

/// RevenueCat placement identifiers (dashboard → Targeting → Placements).
abstract final class PaywallPlacement {
  static const settings = 'settings';
  static const home = 'home';
  static String feature(ProFeature f) => 'feature_${f.name}';
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

  /// Offer/promo codes can be redeemed in this build.
  bool get canRedeemCodes;

  Future<void> init();
  Future<PaywallConfig> paywall({String? placement});
  Future<PurchaseOutcome> purchase(PlanOffer offer);
  Future<Entitlement> restore();

  /// RevenueCat Customer Center (cancel, refund request, restore, contact)
  /// with the store's subscription page as fallback.
  Future<void> manageSubscription();

  /// App Store offer-code sheet / Google Play redeem page.
  Future<void> redeemCode();
}

/// Store pages where an auto-renewing subscription can be cancelled.
Uri platformManagementUrl() => defaultTargetPlatform == TargetPlatform.android
    ? Uri.parse('https://play.google.com/store/account/subscriptions')
    : Uri.parse('https://apps.apple.com/account/subscriptions');

final _playRedeemUrl = Uri.parse('https://play.google.com/redeem');

PlanPeriod? _periodFromName(String? name) {
  for (final p in PlanPeriod.values) {
    if (p.name == name) return p;
  }
  return null;
}

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
  RevenueCatSubscriptionService(this._apiKey, this._prefs);

  static const _kCacheExpiry = 'rc_pro_until';
  static const _kCacheProduct = 'rc_pro_product';

  final String _apiKey;
  final SharedPreferences _prefs;
  final _controller = StreamController<Entitlement>.broadcast();
  Entitlement _current = Entitlement.free;
  String? _error;
  Uri? _managementUrl;

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
  @override
  bool get canRedeemCodes => true;

  bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

  void _emit(Entitlement e) {
    _current = e;
    _controller.add(e);
  }

  void _apply(CustomerInfo info) {
    final url = info.managementURL;
    if (url != null) _managementUrl = Uri.tryParse(url);
    final e = info.entitlements.active[kEntitlementId];
    // Trusted Entitlements: a response whose signature failed is ignored.
    if (e == null || e.verification == VerificationResult.failed) {
      _prefs.remove(_kCacheExpiry);
      _emit(Entitlement.free);
      return;
    }
    final expires = DateTime.tryParse(e.expirationDate ?? '');
    if (expires != null) {
      _prefs.setString(_kCacheExpiry, expires.toIso8601String());
      _prefs.setString(_kCacheProduct, e.productIdentifier);
    }
    _emit(Entitlement(
      isPro: true,
      expiresAt: expires,
      productId: e.productIdentifier,
      willRenew: e.willRenew,
    ));
  }

  /// Last confirmed paid period, used when the store is unreachable.
  Entitlement _cached() {
    final exp = DateTime.tryParse(_prefs.getString(_kCacheExpiry) ?? '');
    if (exp == null || exp.isBefore(DateTime.now())) return Entitlement.free;
    return Entitlement(
      isPro: true,
      expiresAt: exp,
      productId: _prefs.getString(_kCacheProduct),
      offlineCache: true,
    );
  }

  @override
  Future<void> init() async {
    _emit(_cached());
    try {
      await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.warn);
      final config = PurchasesConfiguration(_apiKey)
        ..entitlementVerificationMode = EntitlementVerificationMode.informational;
      await Purchases.configure(config);
      Purchases.addCustomerInfoUpdateListener(_apply);
      // Served from the SDK cache when offline; refreshed in the background.
      _apply(await Purchases.getCustomerInfo());
    } on PlatformException catch (e) {
      _error = 'Mağaza bağlantısı kurulamadı (${e.code}).';
    }
  }

  @override
  Future<PaywallConfig> paywall({String? placement}) async {
    try {
      Offering? offering;
      if (placement != null) {
        offering = await Purchases.getCurrentOfferingForPlacement(placement);
      }
      offering ??= (await Purchases.getOfferings()).current;
      if (offering == null) return const PaywallConfig(offers: []);

      final packages = <PlanPeriod, Package>{};
      for (final pkg in offering.availablePackages) {
        final period = switch (pkg.packageType) {
          PackageType.weekly => PlanPeriod.weekly,
          PackageType.monthly => PlanPeriod.monthly,
          PackageType.annual => PlanPeriod.yearly,
          _ => null,
        };
        if (period != null) packages[period] = pkg;
      }

      // iOS reports intro offers even to users who already used one; only
      // advertise a free trial the user can actually get (3.1.2 / 2.3).
      final eligibility = <String, IntroEligibility>{};
      if (_isIos) {
        final ids = [
          for (final p in packages.values)
            if (p.storeProduct.introductoryPrice != null) p.storeProduct.identifier,
        ];
        if (ids.isNotEmpty) {
          eligibility.addAll(await Purchases.checkTrialOrIntroductoryPriceEligibility(ids));
        }
      }

      final offers = <PlanOffer>[];
      for (final plan in kPlans) {
        final pkg = packages[plan.period];
        if (pkg == null) continue;
        final product = pkg.storeProduct;
        final intro = product.introductoryPrice;
        final eligible = eligibility[product.identifier]?.status !=
            IntroEligibilityStatus.introEligibilityStatusIneligible;
        offers.add(PlanOffer(
          plan: plan,
          priceLabel: product.priceString,
          introLabel: intro == null || !eligible
              ? null
              : intro.price == 0
                  ? '${intro.periodNumberOfUnits} ${_unitTr(intro.periodUnit)} ücretsiz'
                  : 'İlk dönem ${intro.priceString}',
          perWeekLabel: plan.period == PlanPeriod.weekly ||
                  product.pricePerWeekString == null
              ? null
              : '${product.pricePerWeekString} / hafta',
          amount: product.price,
          handle: pkg,
        ));
      }
      return PaywallConfig(
        offers: offers,
        defaultPeriod: _periodFromName(
            offering.getMetadataString(PaywallMetadataKey.defaultPlan, '')),
        headline: _nonEmpty(offering.getMetadataString(PaywallMetadataKey.headline, '')),
        subheadline:
            _nonEmpty(offering.getMetadataString(PaywallMetadataKey.subheadline, '')),
      );
    } on PlatformException catch (e) {
      _error = 'Paketler yüklenemedi (${e.code}).';
      return const PaywallConfig(offers: []);
    }
  }

  static String? _nonEmpty(String s) => s.trim().isEmpty ? null : s.trim();

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

  @override
  Future<void> manageSubscription() async {
    try {
      await RevenueCatUI.presentCustomerCenter(
        onRestoreCompleted: _apply,
      );
      _apply(await Purchases.getCustomerInfo());
    } on PlatformException {
      await launchUrl(managementUrl, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Future<void> redeemCode() async {
    if (_isIos) {
      await Purchases.presentCodeRedemptionSheet();
    } else {
      await launchUrl(_playRedeemUrl, mode: LaunchMode.externalApplication);
    }
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
/// a local expiry date; release builds without store keys become the free
/// edition (everything unlocked, no purchase UI).
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
  @override
  bool get canRedeemCodes => false;

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
  Future<PaywallConfig> paywall({String? placement}) async => PaywallConfig(
        offers: [
          for (final p in kPlans)
            PlanOffer(
              plan: p,
              priceLabel: p.fallbackPrice,
              introLabel: p.trialDays > 0 ? '${p.trialDays} gün ücretsiz' : null,
              perWeekLabel: p.period == PlanPeriod.weekly
                  ? null
                  : '${formatTry(p.fallbackAmount / p.duration.inDays * 7)} / hafta',
              amount: p.fallbackAmount,
            ),
        ],
      );

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

  @override
  Future<void> manageSubscription() =>
      launchUrl(managementUrl, mode: LaunchMode.externalApplication);

  @override
  Future<void> redeemCode() async {}

  /// Developer helper: end the preview subscription.
  Future<void> reset() async {
    await _prefs.remove(_kExpiry);
    await _prefs.remove(_kProduct);
    _load();
  }
}

/// "₺13,46" — Turkish lira formatting for preview prices only (real prices
/// are always localized by the store).
String formatTry(double amount) =>
    '₺${amount.toStringAsFixed(2).replaceAll('.', ',')}';
