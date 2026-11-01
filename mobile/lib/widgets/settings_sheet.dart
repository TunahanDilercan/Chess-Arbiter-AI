import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/arbiter/time_control.dart';
import '../core/chess/notation.dart';
import '../monetization/plans.dart';
import '../monetization/subscription.dart';
import '../providers/providers.dart';
import '../theme/arbiter_tokens.dart';
import 'desk_ui.dart';
import 'piece_image.dart';

/// App settings. Present with [showSettingsSheet].
Future<void> showSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: const _SettingsSheet(),
    ),
  );
}

class _SettingsSheet extends ConsumerStatefulWidget {
  const _SettingsSheet();

  @override
  ConsumerState<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends ConsumerState<_SettingsSheet> {
  late final _arbiter = TextEditingController(text: ref.read(settingsProvider).arbiterName);
  late final _event = TextEditingController(text: ref.read(settingsProvider).defaultEvent);

  @override
  void dispose() {
    _arbiter.dispose();
    _event.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final svc = ref.watch(subscriptionServiceProvider);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            ArbiterSpacing.s5, 0, ArbiterSpacing.s5, ArbiterSpacing.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Ayarlar', style: displayStyle(context, 20)),
            const SizedBox(height: ArbiterSpacing.s4),
            const SectionLabel('Hakem'),
            TextField(
              controller: _arbiter,
              decoration: const InputDecoration(labelText: 'Hakem adı (raporda görünür)'),
              onChanged: n.setArbiterName,
            ),
            const SizedBox(height: ArbiterSpacing.s2),
            TextField(
              controller: _event,
              decoration: const InputDecoration(labelText: 'Şu anki turnuva (yeni oyunlara eklenir)'),
              onChanged: n.setDefaultEvent,
            ),
            const SizedBox(height: ArbiterSpacing.s4),
            const SectionLabel('Varsayılan karne notasyonu'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final l in NotationLocale.values)
                  ChoiceChip(
                    label: Text(l.label),
                    selected: s.locale == l,
                    onSelected: (_) => n.setLocale(l),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hamleleri karnenin harfleriyle göster'),
              subtitle: const Text('Kapalıysa standart İngilizce SAN (K Q R B N)'),
              value: s.showLocalized,
              onChanged: n.setShowLocalized,
            ),
            const SizedBox(height: ArbiterSpacing.s2),
            const SectionLabel('Varsayılan tempo'),
            SegmentedButton<TimeControl>(
              segments: [
                for (final t in TimeControl.values) ButtonSegment(value: t, label: Text(t.label)),
              ],
              selected: {s.timeControl},
              onSelectionChanged: (v) => n.setTimeControl(v.first),
            ),
            const SizedBox(height: ArbiterSpacing.s4),
            const SectionLabel('Görünüm'),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('Sistem'), icon: Icon(Icons.brightness_auto)),
                ButtonSegment(value: ThemeMode.light, label: Text('Açık'), icon: Icon(Icons.light_mode)),
                ButtonSegment(value: ThemeMode.dark, label: Text('Koyu'), icon: Icon(Icons.dark_mode)),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) => n.setThemeMode(v.first),
            ),
            const SizedBox(height: ArbiterSpacing.s3),
            Row(
              children: [
                for (final p in BoardPalette.values) ...[
                  _PaletteSwatch(
                    palette: p,
                    selected: s.palette == p,
                    onTap: () => n.setPalette(p),
                  ),
                  if (p != BoardPalette.values.last) const SizedBox(width: ArbiterSpacing.s3),
                ],
              ],
            ),
            const SizedBox(height: ArbiterSpacing.s3),
            Row(
              children: [
                for (final p in PieceSet.values) ...[
                  _PieceSetSwatch(
                    pieceSet: p,
                    selected: s.pieceSet == p,
                    onTap: () => n.setPieceSet(p),
                  ),
                  if (p != PieceSet.values.last) const SizedBox(width: ArbiterSpacing.s2),
                ],
              ],
            ),
            const SizedBox(height: ArbiterSpacing.s5),
            const SectionLabel('Abonelik ve yasal'),
            if (svc.storeEnabled) ...[
              _LinkTile(
                icon: Icons.workspace_premium_outlined,
                label: 'Hakem Masası Pro',
                onTap: () {
                  Navigator.pop(context);
                  context.push('/pro?from=settings');
                },
              ),
              _LinkTile(
                icon: Icons.restore,
                label: 'Satın alımları geri yükle',
                onTap: () async {
                  final e = await svc.restore();
                  if (context.mounted) {
                    showSnack(context,
                        e.isPro ? 'Aboneliğiniz geri yüklendi.' : 'Etkin abonelik bulunamadı.');
                  }
                },
              ),
              _LinkTile(
                icon: Icons.manage_accounts_outlined,
                label: 'Aboneliği yönet / iptal et',
                onTap: svc.manageSubscription,
              ),
              if (svc.canRedeemCodes)
                _LinkTile(
                  icon: Icons.redeem_outlined,
                  label: 'Promosyon kodu kullan',
                  onTap: svc.redeemCode,
                ),
            ],
            _LinkTile(
              icon: Icons.privacy_tip_outlined,
              label: 'Gizlilik Politikası',
              onTap: () => launchUrl(Uri.parse(kPrivacyUrl)),
            ),
            _LinkTile(
              icon: Icons.description_outlined,
              label: 'Kullanım Koşulları (EULA)',
              onTap: () => launchUrl(Uri.parse(kTermsUrl)),
            ),
            _LinkTile(
              icon: Icons.support_agent_outlined,
              label: 'Destek ve geri bildirim',
              onTap: () => launchUrl(Uri.parse(kSupportUrl)),
            ),
            const SizedBox(height: ArbiterSpacing.s3),
            Text(
              'Oyunlar yalnızca bu cihazda saklanır; internet gerekmez. '
              'Önemli oyunları PGN veya rapor olarak paylaşarak yedekleyin.',
              style: TextStyle(color: c.contentTertiary, fontSize: ArbiterFontSize.labelSm),
            ),
            TextButton(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'Hakem Masası',
                applicationLegalese:
                    'Kural özetleri FIDE Satranç Kuralları (2023) esas alınarak '
                    'hazırlanmıştır; nihai karar hakeme aittir. Hakem Masası FIDE '
                    'veya TSF ile bağlantılı değildir.',
              ),
              child: const Text('Lisanslar ve yasal bilgiler'),
            ),
            if (svc is PreviewSubscriptionService && !kReleaseMode) ...[
              const SizedBox(height: ArbiterSpacing.s3),
              OutlinedButton(
                onPressed: () async {
                  await svc.reset();
                  if (context.mounted) showSnack(context, 'Önizleme aboneliği sıfırlandı.');
                },
                child: const Text('Geliştirici: önizleme aboneliğini sıfırla'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: Icon(icon, color: context.arbiterColors.accentPrimary),
        title: Text(label),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );
}

class _PaletteSwatch extends StatelessWidget {
  const _PaletteSwatch({required this.palette, required this.selected, required this.onTap});
  final BoardPalette palette;
  final bool selected;
  final VoidCallback onTap;

  static const _label = {
    BoardPalette.wood: 'Ahşap',
    BoardPalette.slate: 'Yeşil',
    BoardPalette.mono: 'Gri',
    BoardPalette.oled: 'OLED',
  };

  (Color, Color) get _colors => switch (palette) {
        BoardPalette.wood => (ArbiterPalette.boardWoodSqLight, ArbiterPalette.boardWoodSqDark),
        BoardPalette.slate => (ArbiterPalette.boardSlateSqLight, ArbiterPalette.boardSlateSqDark),
        BoardPalette.mono => (ArbiterPalette.boardMonoSqLight, ArbiterPalette.boardMonoSqDark),
        BoardPalette.oled => (ArbiterPalette.boardOledSqLight, ArbiterPalette.boardOledSqDark),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final (light, dark) = _colors;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ArbiterRadii.md),
                border: Border.all(
                  color: selected ? c.accentPrimary : c.surfaceElevated,
                  width: selected ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(children: [
                Expanded(child: ColoredBox(color: light)),
                Expanded(child: ColoredBox(color: dark)),
              ]),
            ),
            const SizedBox(height: ArbiterSpacing.s1),
            Text(_label[palette]!,
                style: TextStyle(
                    color: selected ? c.accentPrimary : c.contentSecondary,
                    fontSize: ArbiterFontSize.labelSm)),
          ],
        ),
      ),
    );
  }
}

class _PieceSetSwatch extends StatelessWidget {
  const _PieceSetSwatch({required this.pieceSet, required this.selected, required this.onTap});
  final PieceSet pieceSet;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Taş seti ${pieceSet.label}',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          child: Column(
            children: [
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                decoration: BoxDecoration(
                  color: ArbiterPalette.boardWoodSqLight,
                  borderRadius: BorderRadius.circular(ArbiterRadii.md),
                  border: Border.all(
                    color: selected ? c.accentPrimary : c.surfaceElevated,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(child: PieceImage('N', pieceSet: pieceSet, size: 36)),
                    Flexible(child: PieceImage('n', pieceSet: pieceSet, size: 36)),
                  ],
                ),
              ),
              const SizedBox(height: ArbiterSpacing.s1),
              Text(pieceSet.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: selected ? c.accentPrimary : c.contentSecondary,
                      fontSize: ArbiterFontSize.labelSm)),
            ],
          ),
        ),
      ),
    );
  }
}
