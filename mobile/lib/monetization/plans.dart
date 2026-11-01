/// Product catalogue for Hakem Masası Pro.
///
/// Store product IDs and the RevenueCat entitlement are fixed here; real
/// prices always come from the store. [fallbackPrice] is only shown in
/// preview builds (no store configured).
library;

enum PlanPeriod { weekly, monthly, yearly }

class PlanInfo {
  const PlanInfo({
    required this.period,
    required this.productId,
    required this.title,
    required this.subtitle,
    required this.fallbackPrice,
    required this.fallbackAmount,
    required this.perLabel,
    this.badge,
    this.trialDays = 0,
  });

  final PlanPeriod period;
  final String productId;
  final String title;
  final String subtitle;
  final String fallbackPrice;

  /// Numeric preview price (for the per-week comparison in preview builds).
  final double fallbackAmount;
  final String perLabel;
  final String? badge;
  final int trialDays;

  Duration get duration => switch (period) {
        PlanPeriod.weekly => const Duration(days: 7),
        PlanPeriod.monthly => const Duration(days: 30),
        PlanPeriod.yearly => const Duration(days: 365),
      };
}

const kEntitlementId = String.fromEnvironment('RC_ENTITLEMENT', defaultValue: 'pro');

const kPlans = <PlanInfo>[
  PlanInfo(
    period: PlanPeriod.weekly,
    productId: 'hakem_pro_weekly',
    title: 'Turnuva Haftası',
    subtitle: 'Görevli olduğun tek turnuva için.',
    fallbackPrice: '₺79,99',
    fallbackAmount: 79.99,
    perLabel: '/ hafta',
    badge: 'En esnek',
  ),
  PlanInfo(
    period: PlanPeriod.monthly,
    productId: 'hakem_pro_monthly',
    title: 'Aylık',
    subtitle: 'Ayda birden fazla turnuvada görevliysen.',
    fallbackPrice: '₺149,99',
    fallbackAmount: 149.99,
    perLabel: '/ ay',
  ),
  PlanInfo(
    period: PlanPeriod.yearly,
    productId: 'hakem_pro_yearly',
    title: 'Yıllık',
    subtitle: 'Bütün sezon; haftalık en düşük ücret.',
    fallbackPrice: '₺699,99',
    fallbackAmount: 699.99,
    perLabel: '/ yıl',
    badge: 'En avantajlı',
    trialDays: 7,
  ),
];

enum ProFeature {
  claimCheck('Beraberlik talebi doğrulama'),
  illegalMove('Kural dışı hamle danışmanı'),
  flagFall('Süre aşımı (6.9) kontrolü'),
  compare('İki karneyi karşılaştırma'),
  report('PDF hakem raporu'),
  ocr('Fotoğraftan karne okuma'),
  archive('Sınırsız oyun arşivi');

  const ProFeature(this.label);
  final String label;

  /// Features that draw from the free weekly allowance before the paywall.
  bool get usesFreeQuota => this != ProFeature.ocr && this != ProFeature.archive;
}

/// Legal links required next to the purchase button (App Store 3.1.2).
/// Override with --dart-define when the final pages are hosted.
const kTermsUrl = String.fromEnvironment('TERMS_URL',
    defaultValue: 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/');
const kPrivacyUrl = String.fromEnvironment('PRIVACY_URL',
    defaultValue:
        'https://github.com/TunahanDilercan/Chess-Arbiter-AI/blob/main/docs/PRIVACY_TR.md');

const kSupportUrl = String.fromEnvironment('SUPPORT_URL',
    defaultValue: 'https://github.com/TunahanDilercan/Chess-Arbiter-AI/issues');

/// Free tier: core validation is always free; Pro tools get a weekly taste and
/// otherwise show their verdict headline (never a paywall mid-dispute).
const kFreeWeeklyToolUses = 3;
const kFreeArchiveLimit = 10;
