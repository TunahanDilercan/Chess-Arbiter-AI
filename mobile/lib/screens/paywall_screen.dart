import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/arbiter/analysis.dart';
import '../core/arbiter/report.dart';
import '../core/arbiter/sample.dart';
import '../core/chess/notation.dart';
import '../monetization/plans.dart';
import '../monetization/subscription.dart';
import '../providers/providers.dart';
import '../theme/arbiter_tokens.dart';
import '../widgets/chess_board.dart';
import '../widgets/desk_ui.dart';

/// The exact charge and renewal terms shown under the purchase button
/// (App Store 3.1.2: billed amount, period, renewal, how to avoid charges).
String billingTerms(PlanOffer o) {
  final per = switch (o.plan.period) {
    PlanPeriod.weekly => 'her hafta',
    PlanPeriod.monthly => 'her ay',
    PlanPeriod.yearly => 'her yıl',
  };
  return o.introLabel != null
      ? '${o.introLabel}, ardından ${o.priceLabel} $per tahsil edilir. Deneme '
          'bitmeden en az 24 saat önce iptal ederseniz ücret alınmaz.'
      : '${o.priceLabel} $per tahsil edilir; iptal edene kadar otomatik yenilenir.';
}

/// Purchase button label for [o].
String ctaLabel(PlanOffer o) => o.introLabel != null
    ? 'Ücretsiz denemeyi başlat'
    : o.plan.period == PlanPeriod.weekly
        ? 'Turnuva haftasını başlat · ${o.priceLabel}'
        : 'Devam et · ${o.priceLabel} ${o.plan.perLabel}';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, this.feature, this.from});
  final ProFeature? feature;

  /// Where the paywall was opened from (RevenueCat placement).
  final String? from;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  late final Future<PaywallConfig> _config = ref.read(subscriptionServiceProvider).paywall(
        placement: widget.feature != null
            ? PaywallPlacement.feature(widget.feature!)
            : widget.from,
      );
  PlanPeriod? _selected;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // A snackbar from the previous screen must not float over the CTA.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    });
  }

  Future<void> _buy(PlanOffer offer) async {
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    final svc = ref.read(subscriptionServiceProvider);
    final outcome = await svc.purchase(offer);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case PurchaseOutcome.success:
        HapticFeedback.mediumImpact();
        await _showWelcome();
        if (mounted) context.pop(true);
      case PurchaseOutcome.cancelled:
        break;
      case PurchaseOutcome.failed:
        showSnack(context, 'Satın alma tamamlanamadı. Tekrar deneyin.');
      case PurchaseOutcome.unavailable:
        showSnack(context, svc.unavailableReason ?? 'Mağaza şu anda kullanılamıyor.');
    }
  }

  Future<void> _showWelcome() => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) {
          final c = context.arbiterColors;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  ArbiterSpacing.s5, 0, ArbiterSpacing.s5, ArbiterSpacing.s5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.verified, color: c.feedbackSuccess, size: 48),
                  const SizedBox(height: ArbiterSpacing.s2),
                  Text('Pro etkin', textAlign: TextAlign.center, style: displayStyle(context, 24)),
                  const SizedBox(height: ArbiterSpacing.s2),
                  Text(
                    'Talep kontrolü, kural dışı hamle danışmanı, süre aşımı, karne '
                    'karşılaştırma ve PDF rapor artık sınırsız. İyi turnuvalar!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.contentSecondary),
                  ),
                  const SizedBox(height: ArbiterSpacing.s4),
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Masaya dön'),
                  ),
                ],
              ),
            ),
          );
        },
      );

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

  PlanOffer? _chosen(PaywallConfig cfg) {
    if (cfg.offers.isEmpty) return null;
    final want = _selected ?? cfg.defaultPeriod ?? PlanPeriod.weekly;
    return cfg.offers.firstWhere((o) => o.plan.period == want,
        orElse: () => cfg.offers.first);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final svc = ref.watch(subscriptionServiceProvider);
    final ent = ref.watch(entitlementProvider).valueOrNull ?? Entitlement.free;
    ref.watch(quotaTickProvider);
    final quota = ref.watch(quotaProvider);

    return FutureBuilder<PaywallConfig>(
      future: _config,
      builder: (context, snap) {
        final cfg = snap.data;
        final chosen = cfg == null ? null : _chosen(cfg);
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Kapat',
              icon: const Icon(Icons.close),
              onPressed: () => context.pop(false),
            ),
            actions: [
              if (!ent.isPro)
                TextButton(
                  onPressed: _busy ? null : _restore,
                  child: const Text('Geri yükle'),
                ),
            ],
          ),
          bottomNavigationBar: ent.isPro || chosen == null
              ? null
              : _PurchaseBar(
                  offer: chosen,
                  busy: _busy,
                  onBuy: () => _buy(chosen),
                ),
          body: Constrained(
            maxWidth: 560,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  ArbiterSpacing.s4, 0, ArbiterSpacing.s4, ArbiterSpacing.s5),
              children: [
                const _Hero(),
                const SizedBox(height: ArbiterSpacing.s4),
                Text(cfg?.headline ?? 'Hakem Masası Pro', style: displayStyle(context, 28)),
                const SizedBox(height: ArbiterSpacing.s1),
                Text(
                  cfg?.subheadline ??
                      'İtiraz anında doğru kararı saniyeler içinde, maddesiyle ver.',
                  style: TextStyle(color: c.contentSecondary, fontSize: ArbiterFontSize.bodyLg),
                ),
                if (widget.feature != null) ...[
                  const SizedBox(height: ArbiterSpacing.s3),
                  DeskCard(
                    color: c.accentPrimaryMuted,
                    borderColor: c.accentPrimary.withAlpha(90),
                    padding: const EdgeInsets.all(ArbiterSpacing.s3),
                    child: Row(
                      children: [
                        Icon(Icons.lock_clock_outlined, color: c.accentPrimary),
                        const SizedBox(width: ArbiterSpacing.s2),
                        Expanded(
                          child: Text(
                            widget.feature!.usesFreeQuota && quota.remaining == 0
                                ? '"${widget.feature!.label}" için bu haftaki '
                                    '$kFreeWeeklyToolUses ücretsiz hakkınız bitti. Haklar '
                                    '${formatDateTime(quota.resetsAt).split(' ').first} '
                                    'Pazartesi yenilenir.'
                                : '"${widget.feature!.label}" Pro özelliğidir.',
                            style: TextStyle(color: c.contentPrimary),
                          ),
                        ),
                      ],
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
                        : '${ent.willRenew ? 'Yenilenme' : 'Bitiş'}: '
                            '${formatDateTime(ent.expiresAt!)}'
                            '${ent.preview ? ' (önizleme)' : ''}'
                            '${ent.offlineCache ? ' · çevrimdışı doğrulandı' : ''}',
                    children: [
                      if (!ent.preview && !ent.freeEdition)
                        OutlinedButton.icon(
                          onPressed: svc.manageSubscription,
                          icon: const Icon(Icons.manage_accounts_outlined),
                          label: const Text('Aboneliği yönet / iptal et'),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: ArbiterSpacing.s4),
                if (cfg == null)
                  const Padding(
                    padding: EdgeInsets.all(ArbiterSpacing.s5),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (cfg.offers.isEmpty)
                  Text(svc.unavailableReason ?? 'Paketler şu anda yüklenemedi.',
                      style: TextStyle(color: c.feedbackWarning))
                else ...[
                  for (final o in cfg.offers) ...[
                    _PlanCard(
                      offer: o,
                      saving: savingVsWeekly(o, cfg.offers),
                      selected: o.plan.period == chosen!.plan.period,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selected = o.plan.period);
                      },
                    ),
                    const SizedBox(height: ArbiterSpacing.s2),
                  ],
                  if (chosen!.introLabel != null && !ent.isPro) ...[
                    const SizedBox(height: ArbiterSpacing.s2),
                    _TrialTimeline(offer: chosen),
                  ],
                ],
                const SizedBox(height: ArbiterSpacing.s5),
                const _Comparison(),
                const SizedBox(height: ArbiterSpacing.s4),
                const _TrustRow(),
                const SizedBox(height: ArbiterSpacing.s5),
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
                  'yönetebilir veya iptal edebilirsiniz. Abonelik sona erdiğinde Pro '
                  'araçlarının ayrıntıları kilitlenir; oyunlarınız, kayıtlarınız ve '
                  'ücretsiz özellikler kalır. Oyun verileriniz cihazınızda '
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
                    if (svc.canRedeemCodes)
                      TextButton(
                        onPressed: svc.redeemCode,
                        child: const Text('Promosyon kodu'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Sticky purchase area: CTA plus the exact billing terms, always visible
/// whatever the scroll position (App Store 3.1.2 "clear and conspicuous").
class _PurchaseBar extends StatelessWidget {
  const _PurchaseBar({required this.offer, required this.busy, required this.onBuy});
  final PlanOffer offer;
  final bool busy;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    // Large accessibility text still scales, but the pinned bar may not eat
    // the whole screen on small phones.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.6,
      child: _bar(c),
    );
  }

  Widget _bar(ArbiterColors c) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        border: Border(top: BorderSide(color: c.surfaceElevated)),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(24), blurRadius: 16, offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  ArbiterSpacing.s4, ArbiterSpacing.s3, ArbiterSpacing.s4, ArbiterSpacing.s2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: busy ? null : onBuy,
                    child: busy
                        ? const SizedBox(
                            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(ctaLabel(offer), textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: ArbiterSpacing.s2),
                  Text(
                    billingTerms(offer),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.contentSecondary, fontSize: ArbiterFontSize.labelSm),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A real position from the sample game with the verdicts Pro produces.
class _Hero extends StatelessWidget {
  const _Hero();

  static final String _fen = analyzeGame(sampleTokensTr, locale: NotationLocale.tr)
      .plies[49]
      .before
      .fen;

  static const _verdicts = [
    (Icons.cancel, 'Kural dışı hamle', '7.5.1', false),
    (Icons.check_circle, 'Üç tekrar talebi geçerli', '9.2', true),
    (Icons.timer_off_outlined, 'Bayrak: mat imkânı yok', '6.9', true),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Container(
      padding: const EdgeInsets.all(ArbiterSpacing.s3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ArbiterRadii.xl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.accentPrimary.withAlpha(60), c.accentPrimaryMuted],
        ),
        border: Border.all(color: c.accentPrimary.withAlpha(70)),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final boardSize = (box.maxWidth * 0.42).clamp(110.0, 220.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: boardSize,
              child: ExcludeSemantics(
                child: ChessBoard(fen: _fen, errorSquare: 'h6', lastMoveTo: 'h6'),
              ),
            ),
            const SizedBox(width: ArbiterSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (icon, text, article, ok) in _verdicts)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: c.surfaceRaised,
                          borderRadius: BorderRadius.circular(ArbiterRadii.md),
                          border: Border.all(
                              color: (ok ? c.feedbackSuccess : c.feedbackDanger).withAlpha(110)),
                        ),
                        child: Row(
                          children: [
                            Icon(icon,
                                size: 16, color: ok ? c.feedbackSuccess : c.feedbackDanger),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(text,
                                  style: TextStyle(
                                      color: c.contentPrimary,
                                      fontSize: ArbiterFontSize.labelSm,
                                      fontWeight: ArbiterFontWeights.semibold)),
                            ),
                            Text(article,
                                style: TextStyle(
                                    color: c.contentTertiary,
                                    fontFamily: ArbiterFontFamily.mono,
                                    fontSize: ArbiterFontSize.labelSm)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.offer,
    required this.selected,
    required this.onTap,
    this.saving,
  });
  final PlanOffer offer;
  final bool selected;
  final VoidCallback onTap;
  final int? saving;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final p = offer.plan;
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ArbiterRadii.lg),
          boxShadow: selected
              ? [BoxShadow(color: c.accentPrimary.withAlpha(50), blurRadius: 12)]
              : const [],
        ),
        child: DeskCard(
          onTap: onTap,
          color: selected ? c.accentPrimaryMuted : null,
          borderColor: selected ? c.accentPrimary : null,
          padding: const EdgeInsets.all(ArbiterSpacing.s3),
          child: Row(
            children: [
              Icon(selected ? Icons.check_circle : Icons.radio_button_off,
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
                        if (saving != null)
                          Pill('%$saving tasarruf', color: c.feedbackSuccess, filled: true)
                        else if (p.badge != null)
                          Pill(p.badge!, color: c.accentPrimary),
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
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(offer.priceLabel, style: displayStyle(context, 20)),
                      Text(p.perLabel,
                          style: TextStyle(
                              color: c.contentTertiary, fontSize: ArbiterFontSize.labelSm)),
                      if (offer.perWeekLabel != null)
                        Text(offer.perWeekLabel!,
                            style: TextStyle(
                                color: c.contentSecondary, fontSize: ArbiterFontSize.labelSm)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What happens during a free trial — only facts the store guarantees.
class _TrialTimeline extends StatelessWidget {
  const _TrialTimeline({required this.offer});
  final PlanOffer offer;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final steps = [
      (Icons.lock_open, 'Bugün', 'Pro\'nun tamamı açılır. Ücret alınmaz.'),
      (Icons.event_available, 'Deneme süresince',
          'İstediğin an mağaza ayarlarından iptal et; ücret alınmaz.'),
      (Icons.credit_card, 'Deneme bitince',
          '${offer.priceLabel} ${offer.plan.perLabel.replaceAll('/', '').trim()} '
              'başına tahsil edilir.'),
    ];
    return DeskCard(
      padding: const EdgeInsets.all(ArbiterSpacing.s3),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: c.accentPrimaryMuted,
                        child: Icon(steps[i].$1, size: 16, color: c.accentPrimary),
                      ),
                      if (i < steps.length - 1)
                        Expanded(child: Container(width: 2, color: c.surfaceElevated)),
                    ],
                  ),
                  const SizedBox(width: ArbiterSpacing.s3),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: ArbiterSpacing.s3, top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(steps[i].$2,
                              style: TextStyle(
                                  color: c.contentPrimary,
                                  fontWeight: ArbiterFontWeights.semibold)),
                          Text(steps[i].$3,
                              style: TextStyle(
                                  color: c.contentSecondary, fontSize: ArbiterFontSize.bodySm)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Free vs Pro, so the user sees exactly what stays free.
class _Comparison extends StatelessWidget {
  const _Comparison();

  static const _rows = [
    ('Hamle girişi: tahta, karne klavyesi, PGN', '✓', '✓'),
    ('Yasallık kontrolü ve FIDE zaman çizelgesi', '✓', '✓'),
    ('Talep, kural dışı hamle, süre aşımı araçları', '$kFreeWeeklyToolUses/hafta', 'Sınırsız'),
    ('İki karneyi karşılaştırma', '$kFreeWeeklyToolUses/hafta', 'Sınırsız'),
    ('Gerekçe, madde dayanakları ve hakem kaydı', 'Başlık', '✓'),
    ('PDF hakem raporu', '—', '✓'),
    ('Oyun arşivi', '$kFreeArchiveLimit oyun', 'Sınırsız'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    TextStyle head(Color color) => TextStyle(
        color: color, fontWeight: ArbiterFontWeights.semibold, fontSize: ArbiterFontSize.labelMd);
    Widget cell(String t, {bool pro = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Text(
            t,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: t == '—'
                  ? c.contentTertiary
                  : pro
                      ? c.accentPrimary
                      : c.contentSecondary,
              fontWeight: pro ? ArbiterFontWeights.semibold : null,
              fontSize: ArbiterFontSize.bodySm,
            ),
          ),
        );
    return DeskCard(
      padding: const EdgeInsets.symmetric(horizontal: ArbiterSpacing.s3, vertical: ArbiterSpacing.s2),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.2),
          1: FlexColumnWidth(1),
          2: FlexColumnWidth(1),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Neler dahil?', style: head(c.contentPrimary)),
            ),
            Text('Ücretsiz', textAlign: TextAlign.center, style: head(c.contentSecondary)),
            Text('Pro', textAlign: TextAlign.center, style: head(c.accentPrimary)),
          ]),
          for (final (label, free, pro) in _rows)
            TableRow(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.surfaceElevated)),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(label,
                      style: TextStyle(color: c.contentPrimary, fontSize: ArbiterFontSize.bodySm)),
                ),
                cell(free),
                cell(pro, pro: true),
              ],
            ),
        ],
      ),
    );
  }
}

class _TrustRow extends StatelessWidget {
  const _TrustRow();

  static const _items = [
    (Icons.wifi_off, 'İnternetsiz çalışır'),
    (Icons.person_off_outlined, 'Hesap gerekmez'),
    (Icons.event_busy, 'İstediğin an iptal'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (icon, text) in _items)
          Expanded(
            child: Column(
              children: [
                Icon(icon, color: c.accentPrimary),
                const SizedBox(height: 4),
                Text(text,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.contentSecondary, fontSize: ArbiterFontSize.labelSm)),
              ],
            ),
          ),
      ],
    );
  }
}
