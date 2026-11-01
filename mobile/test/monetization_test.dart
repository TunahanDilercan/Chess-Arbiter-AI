import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile/monetization/plans.dart';
import 'package:mobile/monetization/subscription.dart';
import 'package:mobile/screens/paywall_screen.dart';
import 'package:mobile/theme/arbiter_tokens.dart';

void main() {
  test('every piece set ships all twelve pieces', () {
    for (final set in PieceSet.values) {
      for (final c in 'KQRBNPkqrbnp'.split('')) {
        expect(File(set.asset(c)).existsSync(), isTrue, reason: set.asset(c));
      }
    }
  });

  test('preview paywall: billed price first, per-week comparison secondary', () async {
    SharedPreferences.setMockInitialValues({});
    final svc = PreviewSubscriptionService(await SharedPreferences.getInstance(),
        allowPurchases: true);
    final cfg = await svc.paywall();
    expect(cfg.offers.map((o) => o.plan.period), PlanPeriod.values);
    final weekly = cfg.offers.first;
    final yearly = cfg.offers.last;
    expect(weekly.perWeekLabel, isNull);
    expect(yearly.perWeekLabel, '₺13,42 / hafta');
    expect(savingVsWeekly(weekly, cfg.offers), isNull);
    expect(savingVsWeekly(yearly, cfg.offers), 83);
    expect(billingTerms(weekly),
        '₺79,99 her hafta tahsil edilir; iptal edene kadar otomatik yenilenir.');
    expect(billingTerms(yearly), startsWith('7 gün ücretsiz, ardından ₺699,99 her yıl'));
    expect(ctaLabel(yearly), 'Ücretsiz denemeyi başlat');
    expect(ctaLabel(weekly), 'Turnuva haftasını başlat · ₺79,99');
  });

  test('no saving badge when the store gives no numeric prices', () {
    final weekly = PlanOffer(plan: _weekly, priceLabel: r'$4.99');
    final yearly = PlanOffer(plan: _yearly, priceLabel: r'$29.99');
    expect(savingVsWeekly(yearly, [weekly, yearly]), isNull);
  });

  test('release build without store keys is the free edition', () async {
    SharedPreferences.setMockInitialValues({});
    final svc = PreviewSubscriptionService(await SharedPreferences.getInstance(),
        allowPurchases: false);
    await svc.init();
    expect(svc.current.isPro, isTrue);
    expect(svc.current.freeEdition, isTrue);
    expect(svc.storeEnabled, isFalse);
    expect(svc.canRedeemCodes, isFalse);
  });

  test('placements are stable identifiers', () {
    expect(PaywallPlacement.feature(ProFeature.claimCheck), 'feature_claimCheck');
  });
}

final _weekly = kPlans.firstWhere((p) => p.period == PlanPeriod.weekly);
final _yearly = kPlans.firstWhere((p) => p.period == PlanPeriod.yearly);
