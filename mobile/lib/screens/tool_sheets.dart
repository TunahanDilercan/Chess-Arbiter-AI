import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/arbiter/analysis.dart';
import '../core/arbiter/game_record.dart';
import '../core/arbiter/tools.dart';
import '../core/chess/types.dart';
import '../monetization/plans.dart';
import '../providers/providers.dart';
import '../theme/arbiter_tokens.dart';
import '../widgets/chess_board.dart';
import '../widgets/desk_ui.dart';
import '../widgets/pro_gate.dart';

/// 6.9 — "flag fell: can the opponent still mate?"
Future<void> showFlagFallSheet(
  BuildContext context, {
  required GameRecord record,
  required GameAnalysis analysis,
  required int positionIndex,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FlagSheet(
        record: record, analysis: analysis, positionIndex: positionIndex),
  );
}

class _FlagSheet extends ConsumerStatefulWidget {
  const _FlagSheet({required this.record, required this.analysis, required this.positionIndex});
  final GameRecord record;
  final GameAnalysis analysis;
  final int positionIndex;

  @override
  ConsumerState<_FlagSheet> createState() => _FlagSheetState();
}

class _FlagSheetState extends ConsumerState<_FlagSheet> {
  late Side _flagged = widget.analysis.positions[widget.positionIndex].turn;
  FlagVerdict? _verdict;
  bool _full = true;

  Future<void> _check() async {
    final access = await requestToolAccess(context, ref, ProFeature.flagFall);
    if (!mounted) return;
    _full = access == ToolAccess.full;
    setState(() => _verdict =
        checkFlagFall(widget.analysis.positions[widget.positionIndex], _flagged));
  }

  Future<void> _log() async {
    final v = _verdict!;
    await ref.read(gamesProvider.notifier).save(widget.record.withLog(ArbiterLogEntry(
          at: DateTime.now(),
          kind: LogKind.flagFall,
          title: '${_flagged.trName} süre aşımı — ${v.headline}',
          detail: '${positionLabel(widget.positionIndex)}. ${v.details.join(' ')}',
          side: _flagged,
        )));
    if (mounted) {
      Navigator.pop(context);
      showSnack(context, 'Hakem kaydına eklendi.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final pos = widget.analysis.positions[widget.positionIndex];
    final v = _verdict;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            ArbiterSpacing.s4, 0, ArbiterSpacing.s4, ArbiterSpacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Süre aşımı (Madde 6.9)', style: displayStyle(context, 20)),
            const SizedBox(height: ArbiterSpacing.s1),
            Text('${positionLabel(widget.positionIndex)} — rakip mat edebilir mi?',
                style: TextStyle(color: c.contentSecondary)),
            const SizedBox(height: ArbiterSpacing.s3),
            Center(
              child: SizedBox(
                width: 220,
                child: ChessBoard(fen: pos.fen, palette: ref.watch(settingsProvider).palette),
              ),
            ),
            const SizedBox(height: ArbiterSpacing.s3),
            const SectionLabel('Süresi biten taraf'),
            SegmentedButton<Side>(
              segments: [
                for (final s in Side.values) ButtonSegment(value: s, label: Text(s.trName)),
              ],
              selected: {_flagged},
              onSelectionChanged: (s) => setState(() {
                _flagged = s.first;
                _verdict = null;
              }),
            ),
            const SizedBox(height: ArbiterSpacing.s3),
            if (v == null)
              FilledButton.icon(
                onPressed: _check,
                icon: const Icon(Icons.gavel),
                label: const Text('Sonucu belirle'),
              )
            else ...[
              VerdictCard(
                ok: v.result != '?',
                neutral: v.result == '?' || v.result == '1/2-1/2',
                headline: v.headline,
                subtitle: v.result == '?' ? null : 'Sonuç: ${v.result}',
                children: _full
                    ? [for (final d in v.details) Bullet(d), ArticleChips(v.articles)]
                    : [
                        LockedDetails(
                            feature: ProFeature.flagFall,
                            onUnlocked: () => setState(() => _full = true)),
                      ],
              ),
              const SizedBox(height: ArbiterSpacing.s2),
              Text(
                'Malzemeye dayalı değerlendirmedir; kilitli piyon yapıları gibi '
                'özel ölü konumlar tespit edilmez.',
                style: TextStyle(color: c.contentTertiary, fontSize: ArbiterFontSize.labelSm),
              ),
              if (_full) const SizedBox(height: ArbiterSpacing.s3),
              if (_full) OutlinedButton.icon(
                onPressed: _log,
                icon: const Icon(Icons.history_edu),
                label: const Text('Hakem kaydına ekle'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
