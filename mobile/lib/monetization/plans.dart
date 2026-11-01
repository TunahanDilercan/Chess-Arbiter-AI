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
    required this.perLabel,
    this.badge,
    this.trialDays = 0,
  });

  final PlanPeriod period;
  final String productId;
  final String title;
  final String subtitle;
  final String fallbackPrice;
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
    subtitle: 'Hafta sonu turnuvası için. İstediğin hafta al, otomatik '
        'yenilemeyi istediğin an kapat.',
    fallbackPrice: '₺79,99',
    perLabel: '/ hafta',
    badge: 'En esnek',
  ),
  PlanInfo(
    period: PlanPeriod.monthly,
    productId: 'hakem_pro_monthly',
    title: 'Aylık',
    subtitle: 'Ayda birden fazla turnuvada görev alan hakemler için.',
    fallbackPrice: '₺199,99',
    perLabel: '/ ay',
  ),
  PlanInfo(
    period: PlanPeriod.yearly,
    productId: 'hakem_pro_yearly',
    title: 'Yıllık',
    subtitle: 'Bütün sezon. Haftalık plana göre yaklaşık %70 tasarruf.',
    fallbackPrice: '₺1.199,99',
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

/// Free tier: core validation is always free; Pro tools get a weekly taste.
const kFreeWeeklyToolUses = 3;
const kFreeArchiveLimit = 10;
