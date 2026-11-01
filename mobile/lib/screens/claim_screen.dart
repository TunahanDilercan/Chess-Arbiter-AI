import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/arbiter/analysis.dart';
import '../core/arbiter/game_record.dart';
import '../core/arbiter/tools.dart';
import '../core/chess/notation.dart';
import '../core/chess/san.dart';
import '../monetization/plans.dart';
import '../providers/providers.dart';
import '../theme/arbiter_tokens.dart';
import '../widgets/chess_board.dart';
import '../widgets/desk_ui.dart';
import '../widgets/pro_gate.dart';

class ClaimScreen extends ConsumerStatefulWidget {
  const ClaimScreen({super.key, required this.gameId, required this.initialPosition});
  final String gameId;
  final int initialPosition;

  @override
  ConsumerState<ClaimScreen> createState() => _ClaimScreenState();
}

class _ClaimScreenState extends ConsumerState<ClaimScreen> {
  late int _pos = widget.initialPosition;
  ClaimType _type = ClaimType.threefold;
  String? _intended; // localized SAN
  ClaimVerdict? _verdict;
  int? _preview; // position shown on the board when inspecting occurrences
  bool _allMoves = false;
  final _resultKey = GlobalKey();

  void _reset() => setState(() {
        _verdict = null;
        _preview = null;
      });

  Future<void> _verify(GameRecord rec, GameAnalysis a) async {
    if (!await ensureProAccess(context, ref, ProFeature.claimCheck)) return;
    setState(() {
      _preview = null;
      _verdict = checkClaim(a,
          positionIndex: _pos,
          type: _type,
          timeControl: rec.timeControl,
          intendedMove: _intended,
          locale: rec.locale);
    });
    revealAfterFrame(_resultKey);
  }

  Future<void> _log(GameRecord rec) async {
    final v = _verdict!;
    await ref.read(gamesProvider.notifier).save(rec.withLog(ArbiterLogEntry(
          at: DateTime.now(),
          kind: LogKind.claim,
          title: '${v.claimant.trName}: ${v.headline}',
          detail: [
            '${positionLabel(v.positionIndex)}.',
            if (v.intendedSan != null) 'Niyet edilen hamle: ${v.intendedSan}.',
            ...v.details,
            ...v.consequences.take(2),
          ].join(' '),
          ply: v.positionIndex - 1,
          side: v.claimant,
        )));
    if (mounted) showSnack(context, 'Hakem kaydına eklendi.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final rec = ref.watch(gameRecordProvider(widget.gameId));
    final a = ref.watch(analysisProvider(widget.gameId));
    if (rec == null || a == null) return const Scaffold();
    _pos = _pos.clamp(0, a.positions.length - 1);
    final pos = a.positions[_preview ?? _pos];
    final claimant = a.positions[_pos].turn;
    final palette = ref.watch(settingsProvider).palette;

    // Legal moves, those recreating an earlier position first.
    final history = <String, int>{};
    for (var j = 0; j <= _pos; j++) {
      history.update(a.positions[j].repetitionKey, (v) => v + 1, ifAbsent: () => 1);
    }
    final here = a.positions[_pos];
    final moves = [
      for (final m in here.legalMoves)
        (
          localizeSan(toSan(here, m), rec.locale),
          history[here.play(m).repetitionKey] ?? 0,
        ),
    ]..sort((x, y) {
        final r = y.$2.compareTo(x.$2);
        return r != 0 ? r : x.$1.compareTo(y.$1);
      });

    final v = _verdict;
    return Scaffold(
      appBar: AppBar(title: const Text('Beraberlik talebi')),
      body: Constrained(
        child: ListView(
          padding: const EdgeInsets.all(ArbiterSpacing.s4),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: ChessBoard(fen: pos.fen, palette: palette, flipped: claimant.index == 1),
              ),
            ),
            if (_preview != null)
              Padding(
                padding: const EdgeInsets.only(top: ArbiterSpacing.s2),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () => setState(() => _preview = null),
                    icon: const Icon(Icons.undo),
                    label: Text('Gösterilen: ${positionLabel(_preview!)} — talep anına dön'),
                  ),
                ),
              ),
            const SizedBox(height: ArbiterSpacing.s3),
            const SectionLabel('Talep anı'),
            Row(
              children: [
                IconButton(
                  onPressed: _pos > 0 ? () => setState(() { _pos--; _intended = null; _reset(); }) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(positionLabel(_pos),
                          style: TextStyle(
                              color: c.contentPrimary,
                              fontWeight: ArbiterFontWeights.semibold)),
                      Text('Talep eden: ${claimant.trName} (hamle sırası)',
                          style: TextStyle(color: c.contentSecondary)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _pos < a.positions.length - 1
                      ? () => setState(() { _pos++; _intended = null; _reset(); })
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: ArbiterSpacing.s2),
            const SectionLabel('Talep türü'),
            SegmentedButton<ClaimType>(
              segments: [
                for (final t in ClaimType.values) ButtonSegment(value: t, label: Text(t.label)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() { _type = s.first; _reset(); }),
            ),
            const SizedBox(height: ArbiterSpacing.s3),
            SectionLabel('Karneye yazılan niyet edilen hamle (isteğe bağlı)',
                trailing: _intended == null
                    ? null
                    : Text(_intended!, style: TextStyle(color: c.accentPrimary))),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('Yok — mevcut konum'),
                  selected: _intended == null,
                  onSelected: (_) => setState(() { _intended = null; _reset(); }),
                ),
                for (final (san, seen) in moves.where((m) =>
                    _allMoves ||
                    m.$1 == _intended ||
                    (_type == ClaimType.threefold && m.$2 > 0)))
                  ChoiceChip(
                    avatar: seen > 0 && _type == ClaimType.threefold
                        ? Icon(Icons.repeat, size: 14, color: c.feedbackWarning)
                        : null,
                    label: Text(seen > 0 && _type == ClaimType.threefold ? '$san ($seen×)' : san),
                    selected: _intended == san,
                    onSelected: (_) => setState(() { _intended = san; _reset(); }),
                  ),
                ActionChip(
                  avatar: Icon(_allMoves ? Icons.expand_less : Icons.expand_more, size: 16),
                  label: Text(_allMoves ? 'Daha az' : 'Tüm yasal hamleler (${moves.length})'),
                  onPressed: () => setState(() => _allMoves = !_allMoves),
                ),
              ],
            ),
            const SizedBox(height: ArbiterSpacing.s1),
            Text(
              'Tekrar simgeli hamleler daha önce oluşmuş bir konumu yeniden oluşturur.',
              style: TextStyle(color: c.contentTertiary, fontSize: ArbiterFontSize.labelSm),
            ),
            const SizedBox(height: ArbiterSpacing.s4),
            FilledButton.icon(
              onPressed: () => _verify(rec, a),
              icon: const Icon(Icons.balance),
              label: const Text('Talebi doğrula'),
            ),
            if (v != null) ...[
              const SizedBox(height: ArbiterSpacing.s4),
              VerdictCard(
                key: _resultKey,
                ok: v.valid,
                headline: v.headline,
                subtitle: 'Talep eden: ${v.claimant.trName} · ${positionLabel(v.positionIndex)}',
                children: [
                  for (final d in v.details) Bullet(d),
                  for (final nm in v.nearMisses)
                    Bullet(nm.reason, icon: Icons.warning_amber, color: c.feedbackWarning),
                  if (v.matchingPositions.isNotEmpty) ...[
                    const SizedBox(height: ArbiterSpacing.s1),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final i in v.matchingPositions)
                          ActionChip(
                            avatar: const Icon(Icons.visibility, size: 14),
                            label: Text(positionLabel(i)),
                            onPressed: () => setState(() => _preview = i),
                          ),
                      ],
                    ),
                  ],
                  const Divider(height: ArbiterSpacing.s5),
                  const SectionLabel('Hakem ne yapmalı?'),
                  for (final d in v.consequences)
                    Bullet(d, icon: Icons.arrow_right, color: c.accentPrimary),
                  const SizedBox(height: ArbiterSpacing.s2),
                  ArticleChips(v.articles),
                ],
              ),
              const SizedBox(height: ArbiterSpacing.s3),
              OutlinedButton.icon(
                onPressed: () => _log(rec),
                icon: const Icon(Icons.history_edu),
                label: const Text('Hakem kaydına ekle'),
              ),
            ],
            const SizedBox(height: ArbiterSpacing.s4),
            Text(
              'Talep yalnızca karnedeki hamlelere göre değerlendirilir. Saat, taşa '
              'dokunma (9.4) ve talebin usulüne uygun yapılıp yapılmadığı hakem '
              'tarafından ayrıca kontrol edilmelidir.',
              style: TextStyle(color: c.contentTertiary, fontSize: ArbiterFontSize.labelSm),
            ),
          ],
        ),
      ),
    );
  }
}
