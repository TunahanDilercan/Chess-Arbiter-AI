import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../theme/arbiter_tokens.dart';

/// Appearance settings: theme mode (system/light/dark) and board palette.
/// Both are persisted via [settingsProvider]. Present with [showSettingsSheet].
Future<void> showSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _SettingsSheet(),
  );
}

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.arbiterColors;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(ArbiterSpacing.s5, 0,
            ArbiterSpacing.s5, ArbiterSpacing.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Appearance',
              style: TextStyle(
                fontFamily: ArbiterFontFamily.display,
                fontSize: ArbiterFontSize.headingMd,
                fontWeight: ArbiterFontWeights.semibold,
                color: c.contentPrimary,
              ),
            ),
            const SizedBox(height: ArbiterSpacing.s5),

            _SectionLabel('Theme'),
            const SizedBox(height: ArbiterSpacing.s2),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('System'),
                    icon: Icon(Icons.brightness_auto)),
                ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode)),
                ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode)),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (s) => notifier.setThemeMode(s.first),
              style: SegmentedButton.styleFrom(
                backgroundColor: c.surfaceInset,
                foregroundColor: c.contentSecondary,
                selectedBackgroundColor: c.accentPrimaryMuted,
                selectedForegroundColor: c.accentPrimary,
                side: BorderSide(color: c.surfaceElevated),
              ),
            ),
            const SizedBox(height: ArbiterSpacing.s5),

            _SectionLabel('Board palette'),
            const SizedBox(height: ArbiterSpacing.s2),
            Row(
              children: [
                for (final p in BoardPalette.values) ...[
                  _PaletteSwatch(
                    palette: p,
                    selected: settings.palette == p,
                    onTap: () => notifier.setPalette(p),
                  ),
                  if (p != BoardPalette.values.last)
                    const SizedBox(width: ArbiterSpacing.s3),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: c.contentTertiary,
        fontSize: ArbiterFontSize.labelSm,
        fontWeight: ArbiterFontWeights.semibold,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _PaletteSwatch extends StatelessWidget {
  final BoardPalette palette;
  final bool selected;
  final VoidCallback onTap;

  const _PaletteSwatch({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  static const _label = {
    BoardPalette.wood: 'Wood',
    BoardPalette.slate: 'Slate',
    BoardPalette.mono: 'Mono',
    BoardPalette.oled: 'OLED',
  };

  ({Color light, Color dark}) get _colors {
    switch (palette) {
      case BoardPalette.wood:
        return (
          light: ArbiterPalette.boardWoodSqLight,
          dark: ArbiterPalette.boardWoodSqDark
        );
      case BoardPalette.slate:
        return (
          light: ArbiterPalette.boardSlateSqLight,
          dark: ArbiterPalette.boardSlateSqDark
        );
      case BoardPalette.mono:
        return (
          light: ArbiterPalette.boardMonoSqLight,
          dark: ArbiterPalette.boardMonoSqDark
        );
      case BoardPalette.oled:
        return (
          light: ArbiterPalette.boardOledSqLight,
          dark: ArbiterPalette.boardOledSqDark
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final cols = _colors;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ArbiterRadii.md),
                border: Border.all(
                  color: selected ? c.accentPrimary : c.surfaceElevated,
                  width: selected ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  Expanded(child: ColoredBox(color: cols.light)),
                  Expanded(child: ColoredBox(color: cols.dark)),
                ],
              ),
            ),
            const SizedBox(height: ArbiterSpacing.s1),
            Text(
              _label[palette]!,
              style: TextStyle(
                color: selected ? c.accentPrimary : c.contentSecondary,
                fontSize: ArbiterFontSize.labelSm,
                fontWeight:
                    selected ? ArbiterFontWeights.semibold : ArbiterFontWeights.regular,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
