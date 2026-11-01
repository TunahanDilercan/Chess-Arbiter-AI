import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/arbiter/analysis.dart';
import '../core/arbiter/game_record.dart';
import '../core/arbiter/time_control.dart';
import '../core/arbiter/tools.dart';
import '../core/chess/notation.dart';
import '../core/chess/types.dart';
import '../monetization/plans.dart';
import '../providers/providers.dart';
import '../theme/arbiter_tokens.dart';
import '../widgets/chess_board.dart';
import '../widgets/desk_ui.dart';
import '../widgets/pro_gate.dart';

class IllegalMoveScreen extends ConsumerStatefulWidget {
  const IllegalMoveScreen({super.key, required this.gameId, required this.initialPly});
  final String gameId;
  final int initialPly;

  @override
  ConsumerState<IllegalMoveScreen> createState() => _IllegalMoveScreenState();
}

class _IllegalMoveScreenState extends ConsumerState<IllegalMoveScreen> {
  late int _ply = widget.initialPly;
  IrregularityKind _kind = IrregularityKind.illegalMove;
  TimeControl? _tc;
  int? _previous;
  bool _supervised = true;
  bool _opponentMoved = false;
  IllegalMoveAdvice? _advice;
  bool _full = true;
  final _resultKey = GlobalKey();

  Future<void> _advise(GameRecord rec, GameAnalysis a) async {
    final access = await requestToolAccess(context, ref, ProFeature.illegalMove);
    if (!mounted) return;
    final p = a.plies[_ply];
    _full = access == ToolAccess.full;
    setState(() => _advice = adviseIllegalMove(
          before: p.before,
          offender: p.side,
          timeControl: _tc ?? rec.timeControl,
          previousOffences: _previous ?? rec.illegalMoveCount(p.side),
          kind: _kind,
          writtenMove: p.raw,
          adequateSupervision: _supervised,
          opponentHasMovedSince: _opponentMoved,
          locale: rec.locale,
        ));
    HapticFeedback.lightImpact();
    revealAfterFrame(_resultKey);
  }

  Future<void> _log(GameRecord rec, GameAnalysis a) async {
    final adv = _advice!;
    final p = a.plies[_ply];
    await ref.read(gamesProvider.notifier).save(rec.withLog(ArbiterLogEntry(
          at: DateTime.now(),
          kind: LogKind.illegalMove,
          title: '${adv.offender.trName}: ${_kind.label} (${plyLabel(_ply)} "${p.raw}") — ${adv.headline}',
          detail: adv.steps.join(' '),
          ply: _ply,
          side: adv.offender,
        )));
    if (mounted) showSnack(context, 'Kaydedildi: ${adv.offender.trName} için $_ordinal kural dışı hamle.');
  }

  String get _ordinal => '${_advice?.offenceNumber ?? 1}.';

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final rec = ref.watch(gameRecordProvider(widget.gameId));
    final a = ref.watch(analysisProvider(widget.gameId));
    if (rec == null || a == null || a.plies.isEmpty) {
      return Scaffold(
          appBar: AppBar(title: const Text('Kural dışı hamle')),
          body: const EmptyHint(icon: Icons.info_outline, title: 'Önce hamle girin.'));
    }
    _ply = _ply.clamp(0, a.plies.length - 1);
    final p = a.plies[_ply];
    final tc = _tc ?? rec.timeControl;
    final previous = _previous ?? rec.illegalMoveCount(p.side);
    final adv = _advice;
    final palette = ref.watch(settingsProvider).palette;
    final judgeable = p.state != PlyState.notReached && p.state != PlyState.afterGameEnd;

    return Scaffold(
      appBar: AppBar(title: const Text('Kural dışı hamle (7.5)')),
      body: Constrained(
        child: ListView(
          padding: const EdgeInsets.all(ArbiterSpacing.s4),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: _ply > 0 ? () => setState(() { _ply--; _advice = null; _previous = null; }) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text('${plyLabel(_ply)}: "${p.raw}"',
                          style: TextStyle(
                              fontFamily: ArbiterFontFamily.mono,
                              fontSize: ArbiterFontSize.notationLg,
                              color: c.contentPrimary)),
                      Text(p.state == PlyState.illegal
                          ? 'Karnede kural dışı olarak tespit edildi'
                          : 'Tahtada oynanan kural dışı hamleyi kaydetmek için seçin',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.contentSecondary, fontSize: ArbiterFontSize.bodySm)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _ply < a.plies.length - 1
                      ? () => setState(() { _ply++; _advice = null; _previous = null; })
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            if (!judgeable)
              Padding(
                padding: const EdgeInsets.only(bottom: ArbiterSpacing.s3),
                child: Text('Bu hamleden önceki bir hamle çözülmediği için konum bilinmiyor.',
                    style: TextStyle(color: c.feedbackWarning)),
              ),
            const SectionLabel('Düzensizlik türü'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final k in IrregularityKind.values)
                  ChoiceChip(
                    label: Text(k.label),
                    selected: _kind == k,
                    onSelected: (_) => setState(() { _kind = k; _advice = null; }),
                  ),
              ],
            ),
            const SizedBox(height: ArbiterSpacing.s3),
            const SectionLabel('Tempo'),
            SegmentedButton<TimeControl>(
              segments: [
                for (final t in TimeControl.values) ButtonSegment(value: t, label: Text(t.label)),
              ],
              selected: {tc},
              onSelectionChanged: (s) => setState(() { _tc = s.first; _advice = null; }),
            ),
            if (tc != TimeControl.standard) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Yeterli hakem gözetimi var'),
                subtitle: Text(tc == TimeControl.rapid
                    ? 'Bir hakem en fazla 3 oyunu izliyor'
                    : 'Bir hakem tek oyunu izliyor'),
                value: _supervised,
                onChanged: (v) => setState(() { _supervised = v; _advice = null; }),
              ),
              if (!_supervised)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Rakip bir sonraki hamlesini yaptı'),
                  value: _opponentMoved,
                  onChanged: (v) => setState(() { _opponentMoved = v; _advice = null; }),
                ),
            ],
            const SizedBox(height: ArbiterSpacing.s2),
            Row(
              children: [
                Expanded(
                  child: Text('${p.side.trName} tarafının bu oyundaki önceki kural dışı hamleleri',
                      style: TextStyle(color: c.contentPrimary)),
                ),
                IconButton(
                  onPressed: previous > 0
                      ? () => setState(() { _previous = previous - 1; _advice = null; })
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$previous', style: displayStyle(context, 18)),
                IconButton(
                  onPressed: () => setState(() { _previous = previous + 1; _advice = null; }),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: ArbiterSpacing.s3),
            FilledButton.icon(
              onPressed: judgeable ? () => _advise(rec, a) : null,
              icon: const Icon(Icons.gavel),
              label: const Text('Ne yapmalıyım?'),
            ),
            if (adv != null) ...[
              const SizedBox(height: ArbiterSpacing.s4),
              VerdictCard(
                key: _resultKey,
                ok: !adv.isLoss && !adv.isDraw,
                neutral: adv.needsJudgement || adv.isDraw || (!adv.isLoss && !adv.isDraw),
                headline: adv.headline,
                children: !_full
                    ? [
                        Bullet(
                            adv.steps.firstWhere((s) => s.contains('7.5.5'),
                                orElse: () => adv.steps.last),
                            icon: Icons.arrow_right,
                            color: c.accentPrimary),
                        LockedDetails(
                            feature: ProFeature.illegalMove,
                            onUnlocked: () => setState(() => _full = true)),
                      ]
                    : [
                  for (final r in adv.reasons)
                    Bullet(r, icon: Icons.info_outline, color: c.feedbackDanger),
                  const SectionLabel('Adımlar'),
                  for (final s in adv.steps) Bullet(s, icon: Icons.arrow_right, color: c.accentPrimary),
                  if (adv.samePieceMoves.isNotEmpty) ...[
                    const SizedBox(height: ArbiterSpacing.s2),
                    const SectionLabel('Aynı türden taşla yasal hamleler (dokunulan taş, 4.3)'),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final m in adv.samePieceMoves)
                          Chip(label: Text(localizeSan(m, rec.locale))),
                      ],
                    ),
                  ],
                  if (adv.likelyIntended.isNotEmpty) ...[
                    const SizedBox(height: ArbiterSpacing.s2),
                    Text(
                      'Yazıma en yakın yasal hamleler: '
                      '${adv.likelyIntended.map((m) => localizeSan(m, rec.locale)).join(', ')}',
                      style: TextStyle(color: c.contentSecondary),
                    ),
                  ],
                  const SizedBox(height: ArbiterSpacing.s3),
                  const SectionLabel('Yeniden kurulacak konum (7.5.1)'),
                  Center(
                    child: SizedBox(
                      width: 240,
                      child: ChessBoard(
                          fen: adv.reinstated.fen,
                          palette: palette,
                          flipped: adv.offender == Side.black),
                    ),
                  ),
                  const SizedBox(height: ArbiterSpacing.s3),
                  ArticleChips(adv.articles),
                ],
              ),
              if (_full) const SizedBox(height: ArbiterSpacing.s3),
              if (_full) OutlinedButton.icon(
                onPressed: () => _log(rec, a),
                icon: const Icon(Icons.history_edu),
                label: const Text('Hakem kaydına ekle (sayaç artar)'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
