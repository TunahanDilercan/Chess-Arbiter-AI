import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../core/arbiter/analysis.dart';
import '../core/arbiter/game_record.dart';
import '../core/arbiter/report.dart';
import '../core/arbiter/sample.dart';
import '../core/chess/notation.dart';
import '../monetization/plans.dart';
import '../monetization/subscription.dart';
import '../providers/providers.dart';
import '../theme/arbiter_tokens.dart';
import '../widgets/desk_ui.dart';
import '../widgets/pro_gate.dart';
import '../widgets/settings_sheet.dart';
import 'board_entry_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _query = '';
  String? _event;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstRunNotice());
  }

  Future<void> _firstRunNotice() async {
    if (!mounted || ref.read(settingsProvider).onboarded) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Başlamadan önce'),
        content: const Text(
          'Hakem Masası, FIDE Satranç Kuralları (2023) esas alınarak hakem kararına '
          'yardımcı olur; nihai karar her zaman hakeme aittir. Kural metinleri '
          'özettir. Uygulama FIDE veya TSF ile bağlantılı değildir.\n\n'
          'Oyunlar yalnızca bu cihazda saklanır ve uygulama internetsiz çalışır.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anladım'),
          ),
        ],
      ),
    );
    ref.read(settingsProvider.notifier).setOnboarded();
  }

  Future<void> _openSample() async {
    if (!await canCreateGame(context, ref)) return;
    final rec = await ref.read(gamesProvider.notifier).create(
          tokens: sampleTokensTr,
          source: GameSource.typed,
          headers: sampleHeaders,
          locale: NotationLocale.tr,
        );
    if (mounted) context.push('/game/${rec.id}');
  }

  Future<void> _photo() async {
    if (!await ensureProAccess(context, ref, ProFeature.ocr) || !mounted) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Kamera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galeri'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final file = await ref
          .read(imagePickerProvider)
          .pickImage(source: source, imageQuality: 90, maxWidth: 2400);
      if (file != null && mounted) context.push('/crop', extra: file);
    } on PlatformException catch (e) {
      if (mounted) showSnack(context, 'Görüntü açılamadı: ${e.message ?? e.code}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final games = ref.watch(gamesProvider);
    final list = games.valueOrNull ?? const <GameRecord>[];
    final events = {for (final g in list) if (g.event.isNotEmpty) g.event}.toList()..sort();
    final q = _query.toLowerCase();
    final filtered = list.where((g) {
      if (_event != null && g.event != _event) return false;
      if (q.isEmpty) return true;
      return '${g.white} ${g.black} ${g.event} ${g.round} ${g.board}'.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      body: SafeArea(
        child: Constrained(
          maxWidth: 880,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    ArbiterSpacing.s4, ArbiterSpacing.s4, ArbiterSpacing.s4, 0),
                sliver: SliverList.list(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Hakem Masası', style: displayStyle(context, 28)),
                              Text('FIDE kurallarıyla oyun inceleme · internetsiz çalışır',
                                  style: TextStyle(color: c.contentSecondary)),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Ayarlar',
                          onPressed: () => showSettingsSheet(context),
                          icon: const Icon(Icons.tune),
                        ),
                      ],
                    ),
                    if (!games.isLoading && list.isEmpty) _SampleCta(onSample: _openSample),
                    const SizedBox(height: ArbiterSpacing.s4),
                    const _PlanBanner(),
                    const SizedBox(height: ArbiterSpacing.s4),
                    const SectionLabel('Yeni inceleme'),
                    _EntryGrid(
                      onBoard: () => context.push('/board'),
                      onType: () => context.push('/board?mode=keyboard'),
                      onPgn: () => context.push('/import'),
                      onCompare: () => context.push('/compare'),
                      onPosition: () => context.push('/position'),
                      onPhoto: ocrConfigured ? _photo : null,
                    ),
                    const SizedBox(height: ArbiterSpacing.s5),
                    SectionLabel('Oyunlar (${list.length})',
                        trailing: list.length > 3
                            ? SizedBox(
                                width: 180,
                                height: 36,
                                child: TextField(
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    prefixIcon: Icon(Icons.search, size: 18),
                                    hintText: 'Ara',
                                  ),
                                  onChanged: (v) => setState(() => _query = v),
                                ),
                              )
                            : null),
                    if (events.length > 1)
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: const Text('Tümü'),
                                selected: _event == null,
                                onSelected: (_) => setState(() => _event = null),
                              ),
                            ),
                            for (final e in events)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(e),
                                  selected: _event == e,
                                  onSelected: (_) => setState(() => _event = e),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (games.isLoading)
                const SliverToBoxAdapter(
                    child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator())))
              else if (list.isEmpty)
                SliverToBoxAdapter(child: _Welcome(onSample: _openSample))
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                      ArbiterSpacing.s4, ArbiterSpacing.s2, ArbiterSpacing.s4, ArbiterSpacing.s6),
                  sliver: SliverList.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: ArbiterSpacing.s2),
                    itemBuilder: (_, i) => _GameTile(record: filtered[i]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanBanner extends ConsumerWidget {
  const _PlanBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.arbiterColors;
    final ent = ref.watch(entitlementProvider).valueOrNull ?? Entitlement.free;
    ref.watch(quotaTickProvider);
    final quota = ref.watch(quotaProvider);
    if (ent.freeEdition) return const SizedBox.shrink();
    if (ent.isPro) {
      return DeskCard(
        onTap: () => context.push('/pro?from=home'),
        color: c.accentPrimaryMuted,
        borderColor: c.accentPrimary.withAlpha(80),
        padding: const EdgeInsets.all(ArbiterSpacing.s3),
        child: Row(
          children: [
            Icon(Icons.workspace_premium, color: c.accentPrimary),
            const SizedBox(width: ArbiterSpacing.s3),
            Expanded(
              child: Text(
                '${planNameFor(ent.productId)} etkin'
                '${ent.expiresAt == null ? '' : ' · ${ent.willRenew ? 'yenilenme' : 'bitiş'} ${formatDateTime(ent.expiresAt!).split(' ').first}'}',
                style: TextStyle(color: c.contentPrimary),
              ),
            ),
          ],
        ),
      );
    }
    final weekly = kPlans.first;
    return DeskCard(
      onTap: () => context.push('/pro?from=home'),
      padding: const EdgeInsets.all(ArbiterSpacing.s3),
      child: Row(
        children: [
          Icon(Icons.workspace_premium_outlined, color: c.accentPrimary),
          const SizedBox(width: ArbiterSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Turnuvada mısın? ${weekly.title} ile tüm hakem araçları',
                    style: TextStyle(
                        color: c.contentPrimary, fontWeight: ArbiterFontWeights.semibold)),
                Text(
                  'Bu hafta ${quota.remaining}/$kFreeWeeklyToolUses ücretsiz Pro aracı hakkın var.',
                  style: TextStyle(color: c.contentSecondary, fontSize: ArbiterFontSize.bodySm),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: c.contentTertiary),
        ],
      ),
    );
  }
}

class _EntryGrid extends StatelessWidget {
  const _EntryGrid({
    required this.onBoard,
    required this.onType,
    required this.onPgn,
    required this.onCompare,
    required this.onPosition,
    this.onPhoto,
  });

  final VoidCallback onBoard;
  final VoidCallback onType;
  final VoidCallback onPgn;
  final VoidCallback onCompare;
  final VoidCallback onPosition;
  final VoidCallback? onPhoto;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.grid_on, 'Tahtada oyna', 'Hamleleri tahtada yap', onBoard, false),
      (Icons.keyboard_alt_outlined, 'Karneden yaz', 'Satranç klavyesiyle', onType, false),
      (Icons.content_paste_go, 'PGN yapıştır', 'Dosya veya metin', onPgn, false),
      (Icons.compare_arrows, 'Karne karşılaştır', 'Beyaz ↔ Siyah karnesi', onCompare, true),
      (Icons.dashboard_customize_outlined, 'Tahtadaki konum', 'Karnesiz: süre aşımı, ölü konum', onPosition, false),
      if (onPhoto != null)
        (Icons.document_scanner_outlined, 'Fotoğraftan oku', 'Bulut OCR', onPhoto!, true),
    ];
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth > 640 ? 3 : 2;
      final w = (box.maxWidth - (cols - 1) * ArbiterSpacing.s2) / cols;
      return Wrap(
        spacing: ArbiterSpacing.s2,
        runSpacing: ArbiterSpacing.s2,
        children: [
          for (final (icon, title, sub, onTap, pro) in items)
            SizedBox(
              width: w,
              child: _EntryCard(icon: icon, title: title, subtitle: sub, onTap: onTap, pro: pro),
            ),
        ],
      );
    });
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.pro,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool pro;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return DeskCard(
      onTap: onTap,
      padding: const EdgeInsets.all(ArbiterSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: c.accentPrimary, size: 26),
              const Spacer(),
              if (pro) const ProBadge(),
            ],
          ),
          const SizedBox(height: ArbiterSpacing.s2),
          Text(title,
              style: TextStyle(
                  color: c.contentPrimary, fontWeight: ArbiterFontWeights.semibold)),
          Text(subtitle,
              style: TextStyle(color: c.contentSecondary, fontSize: ArbiterFontSize.bodySm)),
        ],
      ),
    );
  }
}

class _GameTile extends ConsumerWidget {
  const _GameTile({required this.record});
  final GameRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.arbiterColors;
    final a = ref.watch(analysisProvider(record.id));
    final (color, label) = a == null
        ? (c.contentTertiary, '…')
        : a.hasProblems
            ? (c.feedbackDanger, 'İnceleme gerekli')
            : a.end != null
                ? (c.accentPrimary, 'Bitti ${a.end!.result}')
                : a.events.any((e) => e.nature == RuleNature.claimable)
                    ? (c.feedbackWarning, 'Talep fırsatı')
                    : (c.feedbackSuccess, 'Temiz');
    final meta = [
      if (record.event.isNotEmpty) record.event,
      if (record.round.isNotEmpty) 'Tur ${record.round}',
      if (record.board.isNotEmpty) 'Masa ${record.board}',
      '${record.tokens.length} yarım hamle',
      formatDateTime(record.updatedAt),
    ].join(' · ');
    return DeskCard(
      onTap: () => context.push('/game/${record.id}'),
      padding: const EdgeInsets.all(ArbiterSpacing.s3),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.contentPrimary, fontWeight: ArbiterFontWeights.semibold)),
                const SizedBox(height: 2),
                Text(meta,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.contentTertiary, fontSize: ArbiterFontSize.labelSm)),
              ],
            ),
          ),
          const SizedBox(width: ArbiterSpacing.s2),
          Flexible(child: Pill(label, color: color)),
        ],
      ),
    );
  }
}

class _SampleCta extends StatelessWidget {
  const _SampleCta({required this.onSample});
  final VoidCallback onSample;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Padding(
      padding: const EdgeInsets.only(top: ArbiterSpacing.s4),
      child: DeskCard(
        color: c.accentPrimaryMuted,
        borderColor: c.accentPrimary.withAlpha(80),
        padding: const EdgeInsets.all(ArbiterSpacing.s3),
        child: Row(
          children: [
            Icon(Icons.school_outlined, color: c.accentPrimary),
            const SizedBox(width: ArbiterSpacing.s3),
            Expanded(
              child: Text('İlk kez mi? Hazır bir itiraz oyununu 30 saniyede inceleyin.',
                  style: TextStyle(color: c.contentPrimary)),
            ),
            TextButton(onPressed: onSample, child: const Text('Örneği aç')),
          ],
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onSample});
  final VoidCallback onSample;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    const steps = [
      (Icons.edit_note, 'Oyunu girin', 'Tahtada oynayın, karneden yazın veya PGN yapıştırın.'),
      (Icons.rule, 'Kuralları görün', 'Kural dışı hamle, üç/beş tekrar, 50/75 hamle, mat/pat anında işaretlenir.'),
      (Icons.gavel, 'Karar verin', 'Talep, ceza ve süre aşımı için FIDE maddesiyle öneri alın; rapor paylaşın.'),
    ];
    return Padding(
      padding: const EdgeInsets.all(ArbiterSpacing.s4),
      child: DeskCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('İnceleme masasına hoş geldiniz', style: displayStyle(context, 20)),
            const SizedBox(height: ArbiterSpacing.s3),
            for (final (icon, title, body) in steps)
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
            FilledButton.tonalIcon(
              onPressed: onSample,
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('Örnek itiraz oyununu aç'),
            ),
          ],
        ),
      ),
    );
  }
}
