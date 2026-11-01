import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/arbiter/analysis.dart';
import '../core/arbiter/game_record.dart';
import '../core/chess/fuzzy.dart';
import '../core/chess/notation.dart';
import '../core/chess/san.dart';
import '../providers/providers.dart';
import '../theme/arbiter_tokens.dart';
import '../widgets/analysis_panels.dart';
import '../widgets/chess_board.dart';
import '../widgets/chess_keyboard.dart';
import '../widgets/desk_ui.dart';

List<String> pieceLettersFor(NotationLocale l) => switch (l) {
      NotationLocale.en => const ['K', 'Q', 'R', 'B', 'N'],
      NotationLocale.tr => const ['Ş', 'V', 'K', 'F', 'A'],
      NotationLocale.de => const ['K', 'D', 'T', 'L', 'S'],
      NotationLocale.fr => const ['R', 'D', 'T', 'F', 'C'],
      NotationLocale.es => const ['R', 'D', 'T', 'A', 'C'],
    };

Future<void> showMoveEditSheet(
  BuildContext context, {
  required GameRecord record,
  required GameAnalysis analysis,
  required int ply,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _MoveEditSheet(record: record, analysis: analysis, ply: ply),
  );
}

class _MoveEditSheet extends ConsumerStatefulWidget {
  const _MoveEditSheet({required this.record, required this.analysis, required this.ply});
  final GameRecord record;
  final GameAnalysis analysis;
  final int ply;

  @override
  ConsumerState<_MoveEditSheet> createState() => _MoveEditSheetState();
}

class _MoveEditSheetState extends ConsumerState<_MoveEditSheet> {
  String _input = '';

  PlyAnalysis get _ply => widget.analysis.plies[widget.ply];
  NotationLocale get _loc => widget.record.locale;

  List<String> _suggestions() {
    final pos = _ply.before;
    if (_ply.state == PlyState.notReached || _ply.state == PlyState.afterGameEnd) {
      return const [];
    }
    final written = normalizeMove(_input.isEmpty ? _ply.raw : _input, _loc);
    final ranked = rankMoves(pos, written).map((r) => localizeSan(r.san, _loc));
    if (_input.isEmpty) return ranked.take(8).toList();
    final prefix = ranked.where((s) => s.startsWith(_input)).toList();
    return (prefix.isNotEmpty ? prefix : ranked).take(8).toList();
  }

  Future<void> _apply(List<String> tokens, String title) async {
    final rec = widget.record;
    final updated = rec.copyWith(tokens: tokens).withLog(ArbiterLogEntry(
          at: DateTime.now(),
          kind: LogKind.correction,
          title: title,
          ply: widget.ply,
          side: _ply.side,
        ));
    final messenger = ScaffoldMessenger.of(context);
    final games = ref.read(gamesProvider.notifier);
    await games.save(updated);
    HapticFeedback.selectionClick();
    if (mounted) Navigator.pop(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Kaydedildi: $title'),
        action: SnackBarAction(label: 'Geri al', onPressed: () => games.save(rec)),
      ));
  }

  Future<void> _replace(String token) {
    final t = token.trim().isEmpty ? '?' : token.trim();
    final tokens = [...widget.record.tokens]..[widget.ply] = t;
    return _apply(tokens, '${plyLabel(widget.ply)}: "${_ply.raw}" → "$t"');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final settings = ref.watch(settingsProvider);
    final p = _ply;
    final parsed = _input.isEmpty ? null : parseMove(p.before, normalizeMove(_input, _loc));
    final canJudge = p.state != PlyState.notReached && p.state != PlyState.afterGameEnd;

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: ArbiterSpacing.s4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 132,
                    child: ChessBoard(
                      fen: p.before.fen,
                      palette: settings.palette,
                      flipped: p.side.index == 1,
                    ),
                  ),
                  const SizedBox(width: ArbiterSpacing.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${plyLabel(widget.ply)} hamlesi',
                            style: displayStyle(context, 18)),
                        const SizedBox(height: ArbiterSpacing.s1),
                        Text('Karnede: "${p.raw.isEmpty ? '?' : p.raw}"',
                            style: TextStyle(
                                fontFamily: ArbiterFontFamily.mono,
                                color: c.contentSecondary)),
                        const SizedBox(height: ArbiterSpacing.s2),
                        Pill(plyStateLabel(p.state), color: plyColor(context, p.state)),
                        for (final r in [...p.reasons, ...p.warnings])
                          Padding(
                            padding: const EdgeInsets.only(top: ArbiterSpacing.s2),
                            child: Text(r,
                                style: TextStyle(
                                    color: c.contentSecondary,
                                    fontSize: ArbiterFontSize.bodySm)),
                          ),
                        if (!canJudge)
                          Padding(
                            padding: const EdgeInsets.only(top: ArbiterSpacing.s2),
                            child: Text(
                                'Önceki bir hamle çözülmeden bu hamle değerlendirilemez. '
                                'Yine de karnedeki yazımı düzeltebilirsiniz.',
                                style: TextStyle(
                                    color: c.contentSecondary,
                                    fontSize: ArbiterFontSize.bodySm)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: ArbiterSpacing.s3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: ArbiterSpacing.s3),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.playlist_add, size: 16),
                    label: const Text('Öncesine eksik hamle ekle'),
                    onPressed: () => _apply(
                        [...widget.record.tokens]..insert(widget.ply, '?'),
                        '${plyLabel(widget.ply)} öncesine eksik hamle eklendi'),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.playlist_remove, size: 16),
                    label: const Text('Fazla hamleyi sil'),
                    onPressed: () => _apply(
                        [...widget.record.tokens]..removeAt(widget.ply),
                        '${plyLabel(widget.ply)} "${p.raw}" silindi'),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.help_outline, size: 16),
                    label: const Text('Bilinmiyor (?)'),
                    onPressed: () => _replace('?'),
                  ),
                ],
              ),
            ),
            if (parsed != null && canJudge)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    ArbiterSpacing.s4, ArbiterSpacing.s2, ArbiterSpacing.s4, 0),
                child: Text(
                  parsed.isResolved
                      ? '✓ Yasal: ${localizeSan(toSan(p.before, parsed.move!), _loc)}'
                      : parsed.status == SanParseStatus.ambiguous
                          ? '… Belirsiz — taşı belirtin (ör. sütun harfi)'
                          : '✗ Bu konumda yasal değil (yine de karnedeki gibi kaydedebilirsiniz)',
                  style: TextStyle(
                    color: parsed.isResolved ? c.feedbackSuccess : c.feedbackWarning,
                    fontWeight: ArbiterFontWeights.semibold,
                  ),
                ),
              ),
            const SizedBox(height: ArbiterSpacing.s2),
            ChessKeyboard(
              currentInput: _input,
              suggestions: _suggestions(),
              pieceLetters: pieceLettersFor(_loc),
              confirmLabel: 'Kaydet',
              onChar: (ch) => setState(() => _input += ch),
              onSuggestion: (s) => _replace(s),
              onBackspace: () => setState(() {
                if (_input.isNotEmpty) _input = _input.substring(0, _input.length - 1);
              }),
              onClear: () => setState(() => _input = ''),
              onConfirm: () {
                if (_input.isNotEmpty) _replace(_input);
              },
            ),
          ],
        ),
      ),
    );
  }
}
