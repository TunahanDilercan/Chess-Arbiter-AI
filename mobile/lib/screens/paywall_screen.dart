import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/arbiter/report.dart';
import '../monetization/plans.dart';
import '../monetization/subscription.dart';
import '../providers/providers.dart';
import '../theme/arbiter_tokens.dart';
import '../widgets/desk_ui.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, this.feature});
  final ProFeature? feature;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  late final Future<List<PlanOffer>> _offers =
      ref.read(subscriptionServiceProvider).offers();
  PlanPeriod _selected = PlanPeriod.weekly;
  bool _busy = false;

  static const _benefits = [
    (Icons.balance, 'Beraberlik talebi doğrulama', 'Üç tekrar ve 50 hamle; niyet edilen hamle, 9.2.2 farkları, ceza süresi.'),
    (Icons.gpp_maybe_outlined, 'Kural dışı hamle danışmanı', '7.5.5 ceza merdiveni, tempo ve gözetim durumuna göre adım adım karar.'),
    (Icons.timer_off_outlined, 'Süre aşımı kontrolü', 'Bayrak düştüğünde rakip mat edebilir mi? (6.9)'),
    (Icons.compare_arrows, 'İki karneyi karşılaştırma', 'Uyuşmazlıkta ayrışan ve eksik hamleyi saniyede bulur.'),
    (Icons.picture_as_pdf_outlined, 'PDF hakem raporu', 'İtiraz kurulu ve başhakem için maddeli, zaman damgalı rapor.'),
    (Icons.all_inclusive, 'Sınırsız arşiv', 'Turnuvadaki bütün oyunları cihazında sakla.'),
  ];

  Future<void> _buy(PlanOffer offer) async {
    setState(() => _busy = true);
    final svc = ref.read(subscriptionServiceProvider);
    final outcome = await svc.purchase(offer);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case PurchaseOutcome.success:
        showSnack(context, 'Pro etkin. İyi turnuvalar!');
        context.pop(true);
      case PurchaseOutcome.cancelled:
        break;
      case PurchaseOutcome.failed:
        showSnack(context, 'Satın alma tamamlanamadı. Tekrar deneyin.');
      case PurchaseOutcome.unavailable:
        showSnack(context, svc.unavailableReason ?? 'Mağaza şu anda kullanılamıyor.');
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    final e = await ref.read(subscriptionServiceProvider).restore();
    if (!mounted) return;
    setState(() => _busy = false);
    if (e.isPro) {
      showSnack(context, 'Aboneliğiniz geri yüklendi.');
      context.pop(true);
    } else {
      showSnack(context, 'Etkin abonelik bulunamadı.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final svc = ref.watch(subscriptionServiceProvider);
    final ent = ref.watch(entitlementProvider).valueOrNull ?? Entitlement.free;
    ref.watch(quotaTickProvider);
    final quota = ref.watch(quotaProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.pop(false)),
      ),
      body: Constrained(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(ArbiterSpacing.s5, 0, ArbiterSpacing.s5, ArbiterSpacing.s6),
          children: [
            Text('Hakem Masası Pro', style: displayStyle(context, 30)),
            const SizedBox(height: ArbiterSpacing.s1),
            Text('İtiraz anında doğru kararı saniyeler içinde, maddesiyle ver.',
                style: TextStyle(color: c.contentSecondary, fontSize: ArbiterFontSize.bodyLg)),
            if (widget.feature != null) ...[
              const SizedBox(height: ArbiterSpacing.s3),
              DeskCard(
                color: c.accentPrimaryMuted,
                borderColor: c.accentPrimary.withAlpha(90),
                padding: const EdgeInsets.all(ArbiterSpacing.s3),
                child: Text(
                  widget.feature!.usesFreeQuota && quota.remaining == 0
                      ? '"${widget.feature!.label}" için bu haftaki $kFreeWeeklyToolUses ücretsiz '
                          'hakkınız bitti. Haklar ${formatDateTime(quota.resetsAt).split(' ').first} '
                          'Pazartesi yenilenir.'
                      : '"${widget.feature!.label}" Pro özelliğidir.',
                  style: TextStyle(color: c.contentPrimary),
                ),
              ),
            ],
            if (ent.isPro) ...[
              const SizedBox(height: ArbiterSpacing.s3),
              VerdictCard(
                ok: true,
                headline: '${planNameFor(ent.productId)} etkin',
                subtitle: ent.expiresAt == null
                    ? null
                    : '${ent.willRenew ? 'Yenilenme' : 'Bitiş'}: ${formatDateTime(ent.expiresAt!)}'
                        '${ent.preview ? ' (önizleme)' : ''}',
              ),
            ],
            const SizedBox(height: ArbiterSpacing.s4),
            FutureBuilder<List<PlanOffer>>(
              future: _offers,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final offers = snap.data!;
                if (offers.isEmpty) {
                  return Text(svc.unavailableReason ?? 'Paketler şu anda yüklenemedi.',
                      style: TextStyle(color: c.feedbackWarning));
                }
                final chosen = offers.firstWhere((o) => o.plan.period == _selected,
                    orElse: () => offers.first);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final o in offers) ...[
                      _PlanCard(
                        offer: o,
                        selected: o.plan.period == chosen.plan.period,
                        onTap: () => setState(() => _selected = o.plan.period),
                      ),
                      const SizedBox(height: ArbiterSpacing.s2),
                    ],
                    const SizedBox(height: ArbiterSpacing.s2),
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: _busy || ent.isPro ? null : () => _buy(chosen),
                      child: _busy
                          ? const SizedBox(
                              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(chosen.plan.period == PlanPeriod.weekly
                              ? 'Turnuva haftasını başlat · ${chosen.priceLabel}'
                              : 'Devam et · ${chosen.priceLabel} ${chosen.plan.perLabel}'),
                    ),
                  ],
                );
              },
            ),
            TextButton(onPressed: _busy ? null : _restore, child: const Text('Satın alımları geri yükle')),
            const SizedBox(height: ArbiterSpacing.s4),
            for (final (icon, title, body) in _benefits)
              Padding(
                padding: const EdgeInsets.only(bottom: ArbiterSpacing.s3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: c.accentPrimary),
                    const SizedBox(width: ArbiterSpacing.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: TextStyle(
                                  color: c.contentPrimary,
                                  fontWeight: ArbiterFontWeights.semibold)),
                          Text(body, style: TextStyle(color: c.contentSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              'Ücretsiz sürümde hamle girişi, yasallık kontrolü, FIDE kural zaman '
              'çizelgesi ve PGN paylaşımı her zaman açık; Pro araçlarını her hafta '
              '$kFreeWeeklyToolUses kez ücretsiz deneyebilirsiniz.',
              style: TextStyle(color: c.contentTertiary, fontSize: ArbiterFontSize.bodySm),
            ),
            const SizedBox(height: ArbiterSpacing.s4),
            if (svc.isPreview)
              Padding(
                padding: const EdgeInsets.only(bottom: ArbiterSpacing.s2),
                child: Text(
                  'Önizleme modu: mağaza bağlı değil, gerçek ödeme alınmaz. '
                  'Fiyatlar örnek amaçlıdır.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.feedbackWarning, fontSize: ArbiterFontSize.labelSm),
                ),
              ),
            Text(
              'Abonelik, dönem bitiminden en az 24 saat önce iptal edilmezse aynı '
              'süre ve ücretle otomatik yenilenir. Ödeme App Store / Google Play '
              'hesabınızdan alınır; aboneliği mağaza hesap ayarlarından '
              'yönetebilir veya iptal edebilirsiniz. Oyun verileriniz cihazınızda '
              'kalır. Hakem Masası; FIDE veya TSF ile bağlantılı değildir, kural '
              'özetleri bilgilendirme amaçlıdır ve nihai karar hakeme aittir.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.contentTertiary, fontSize: ArbiterFontSize.labelSm),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                TextButton(
                  onPressed: () => launchUrl(Uri.parse(kTermsUrl)),
                  child: const Text('Kullanım Koşulları (EULA)'),
                ),
                TextButton(
                  onPressed: () => launchUrl(Uri.parse(kPrivacyUrl)),
                  child: const Text('Gizlilik Politikası'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.offer, required this.selected, required this.onTap});
  final PlanOffer offer;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final p = offer.plan;
    return DeskCard(
      onTap: onTap,
      color: selected ? c.accentPrimaryMuted : null,
      borderColor: selected ? c.accentPrimary : null,
      padding: const EdgeInsets.all(ArbiterSpacing.s3),
      child: Row(
        children: [
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? c.accentPrimary : c.contentTertiary),
          const SizedBox(width: ArbiterSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: ArbiterSpacing.s2,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(p.title,
                        style: TextStyle(
                            color: c.contentPrimary,
                            fontWeight: ArbiterFontWeights.semibold,
                            fontSize: ArbiterFontSize.bodyLg)),
                    if (p.badge != null) Pill(p.badge!, color: c.accentPrimary),
                  ],
                ),
                const SizedBox(height: 2),
                Text(p.subtitle,
                    style: TextStyle(color: c.contentSecondary, fontSize: ArbiterFontSize.bodySm)),
                if (offer.introLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(offer.introLabel!,
                        style: TextStyle(
                            color: c.feedbackSuccess,
                            fontSize: ArbiterFontSize.bodySm,
                            fontWeight: ArbiterFontWeights.semibold)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: ArbiterSpacing.s2),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(offer.priceLabel, style: displayStyle(context, 18)),
              Text(p.perLabel,
                  style: TextStyle(color: c.contentTertiary, fontSize: ArbiterFontSize.labelSm)),
            ],
          ),
        ],
      ),
    );
  }
}
