import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/arbiter/analysis.dart';
import '../core/arbiter/compare.dart';
import '../core/arbiter/game_record.dart';
import '../core/chess/notation.dart';
import '../core/chess/pgn.dart';
import '../monetization/plans.dart';
import '../providers/providers.dart';
import '../theme/arbiter_tokens.dart';
import '../widgets/desk_ui.dart';
import '../widgets/pro_gate.dart';
import 'board_entry_screen.dart';

/// Reconstructs a disputed game from both players' scoresheets.
class CompareScreen extends ConsumerStatefulWidget {
  const CompareScreen({super.key, this.gameId});
  final String? gameId;

  @override
  ConsumerState<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends ConsumerState<CompareScreen> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  late NotationLocale _locA = ref.read(settingsProvider).locale;
  late NotationLocale _locB = ref.read(settingsProvider).locale;
  SheetComparison? _result;
  bool _full = true;
  final _resultKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final rec = widget.gameId == null ? null : ref.read(gameRecordProvider(widget.gameId!));
    if (rec != null) {
      _a.text = rec.tokens.join(' ');
      _locA = rec.locale;
    }
  }

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  List<String> _tokens(String text) {
    final games = parsePgn(text);
    return games.isEmpty ? const [] : games.first.moves;
  }

  Future<void> _compare() async {
    final a = _tokens(_a.text), b = _tokens(_b.text);
    if (a.isEmpty || b.isEmpty) {
      showSnack(context, 'İki karneyi de girin.');
      return;
    }
    final access = await requestToolAccess(context, ref, ProFeature.compare);
    if (!mounted) return;
    setState(() {
      _full = access == ToolAccess.full;
      _result = compareSheets(a, b, localeA: _locA, localeB: _locB);
    });
    revealAfterFrame(_resultKey);
  }

  Future<void> _use(bool useA) async {
    final r = _result!;
    final tokens = _tokens(useA ? _a.text : _b.text);
    final locale = useA ? _locA : _locB;
    final summary = r.summary.join(' ');
    final notifier = ref.read(gamesProvider.notifier);
    final existing = widget.gameId == null ? null : ref.read(gameRecordProvider(widget.gameId!));
    final entry = ArbiterLogEntry(
      at: DateTime.now(),
      kind: LogKind.comparison,
      title: 'Karneler karşılaştırıldı; ${useA ? 'A' : 'B'} karnesi esas alındı',
      detail: summary,
    );
    if (existing != null) {
      await notifier.save(existing.copyWith(tokens: tokens, locale: locale).withLog(entry));
      if (mounted) context.pop();
      return;
    }
    if (!await canCreateGame(context, ref)) return;
    final rec = await notifier.create(tokens: tokens, source: GameSource.comparison, locale: locale);
    await notifier.save(rec.withLog(entry));
    if (mounted) context.pushReplacement('/game/${rec.id}');
  }

  Widget _sheetField(String label, TextEditingController ctl, NotationLocale loc,
      ValueChanged<NotationLocale> onLoc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(label,
            trailing: DropdownButton<NotationLocale>(
              value: loc,
              underline: const SizedBox.shrink(),
              items: [
                for (final l in NotationLocale.values)
                  DropdownMenuItem(value: l, child: Text(l.code)),
              ],
              onChanged: (v) => v == null ? null : onLoc(v),
            )),
        TextField(
          controller: ctl,
          minLines: 3,
          maxLines: 6,
          style: const TextStyle(fontFamily: ArbiterFontFamily.mono, fontSize: 14),
          decoration: const InputDecoration(hintText: '1. e4 e5 2. Af3 …'),
          onChanged: (_) => setState(() => _result = null),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Karne karşılaştır')),
      body: Constrained(
        child: ListView(
          padding: const EdgeInsets.all(ArbiterSpacing.s4),
          children: [
            Text(
              'Beyaz ve Siyah oyuncunun karnelerini ayrı ayrı girin. Uygulama '
              'farklılaşan hamleyi, eksik/fazla yazılan hamleyi ve hangi karnenin '
              'yasal olarak ilerlediğini gösterir.',
              style: TextStyle(color: c.contentSecondary),
            ),
            const SizedBox(height: ArbiterSpacing.s3),
            _sheetField('A — Beyaz\'ın karnesi', _a, _locA, (l) => setState(() => _locA = l)),
            const SizedBox(height: ArbiterSpacing.s3),
            _sheetField('B — Siyah\'ın karnesi', _b, _locB, (l) => setState(() => _locB = l)),
            const SizedBox(height: ArbiterSpacing.s4),
            FilledButton.icon(
              onPressed: _compare,
              icon: const Icon(Icons.compare_arrows),
              label: const Text('Karşılaştır'),
            ),
            if (r != null) ...[
              const SizedBox(height: ArbiterSpacing.s4),
              VerdictCard(
                key: _resultKey,
                ok: r.identical,
                neutral: !r.identical,
                headline: r.identical ? 'Karneler aynı' : 'Karneler farklı',
                children: _full
                    ? [for (final s in r.summary) Bullet(s)]
                    : [
                        for (final s in r.summary.take(2)) Bullet(s),
                        LockedDetails(
                            feature: ProFeature.compare,
                            onUnlocked: () => setState(() => _full = true)),
                      ],
              ),
              if (_full) ...[
              const SizedBox(height: ArbiterSpacing.s3),
              _AlignedTable(result: r),
              const SizedBox(height: ArbiterSpacing.s3),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _use(true),
                      child: const Text('A karnesini kullan'),
                    ),
                  ),
                  const SizedBox(width: ArbiterSpacing.s3),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _use(false),
                      child: const Text('B karnesini kullan'),
                    ),
                  ),
                ],
              ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

String _shortLabel(int ply) => '${ply ~/ 2 + 1}${ply.isEven ? '.' : '…'}';

class _AlignedTable extends StatelessWidget {
  const _AlignedTable({required this.result});
  final SheetComparison result;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    TextStyle mono(Color color, {bool bold = false}) => TextStyle(
        fontFamily: ArbiterFontFamily.mono,
        color: color,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400);

    bool problem(GameAnalysis g, int? i) =>
        i != null && i < g.plies.length && !g.plies[i].state.isResolved;

    Widget cell(String? text, GameAnalysis g, int? i, RowKind kind) => Row(
          children: [
            Flexible(
              child: Text(
                text ?? '— eksik',
                overflow: TextOverflow.ellipsis,
                style: mono(text == null ? c.feedbackWarning : c.contentPrimary,
                    bold: kind != RowKind.same),
              ),
            ),
            if (text != null && problem(g, i))
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.warning_amber, size: 14, color: c.feedbackWarning),
              ),
          ],
        );

    return DeskCard(
      padding: const EdgeInsets.all(ArbiterSpacing.s2),
      child: Column(
        children: [
          Row(children: [
            const SizedBox(width: 48),
            Expanded(child: Text('A', style: mono(c.contentTertiary, bold: true))),
            Expanded(child: Text('B', style: mono(c.contentTertiary, bold: true))),
          ]),
          const Divider(),
          for (final row in result.rows)
            Container(
              color: switch (row.kind) {
                RowKind.same => null,
                RowKind.different => c.feedbackDanger.withAlpha(24),
                _ => c.feedbackWarning.withAlpha(30),
              },
              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    child: Text(
                      _shortLabel(row.aIndex ?? row.bIndex ?? 0),
                      style: mono(c.contentTertiary),
                    ),
                  ),
                  Expanded(child: cell(row.a, result.analysisA, row.aIndex, row.kind)),
                  Expanded(child: cell(row.b, result.analysisB, row.bIndex, row.kind)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
