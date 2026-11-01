import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/arbiter/fide.dart';
import '../core/arbiter/material.dart';
import '../core/arbiter/tools.dart';
import '../core/chess/position.dart';
import '../core/chess/types.dart';
import '../monetization/plans.dart';
import '../providers/providers.dart';
import '../theme/arbiter_tokens.dart';
import '../widgets/chess_board.dart';
import '../widgets/desk_ui.dart';
import '../widgets/pro_gate.dart';

/// Build the position that is on the physical board (no scoresheet needed —
/// typical in rapid/blitz) and judge dead position (5.2.2) and flag fall (6.9).
class PositionSetupScreen extends ConsumerStatefulWidget {
  const PositionSetupScreen({super.key, this.initialFen});
  final String? initialFen;

  @override
  ConsumerState<PositionSetupScreen> createState() => _PositionSetupScreenState();
}

class _PositionSetupScreenState extends ConsumerState<PositionSetupScreen> {
  final _board = List<Piece?>.filled(64, null);
  Side _turn = Side.white;
  Piece? _brush = const Piece(Side.white, Role.king); // null = eraser
  FlagVerdict? _verdict;
  Side? _flagged;
  final _resultKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load(widget.initialFen ?? Position.startFen);
  }

  void _load(String fen) {
    final pos = Position.fromFen(fen);
    for (var i = 0; i < 64; i++) {
      _board[i] = pos.pieceAt(i);
    }
    _turn = pos.turn;
    _verdict = null;
  }

  void _clear() => setState(() {
        _board.fillRange(0, 64, null);
        _board[Square.parse('e1')!] = const Piece(Side.white, Role.king);
        _board[Square.parse('e8')!] = const Piece(Side.black, Role.king);
        _verdict = null;
      });

  String get _fen {
    final sb = StringBuffer();
    for (var rank = 7; rank >= 0; rank--) {
      var empty = 0;
      for (var file = 0; file < 8; file++) {
        final p = _board[Square.at(file, rank)];
        if (p == null) {
          empty++;
        } else {
          if (empty > 0) sb.write(empty);
          empty = 0;
          sb.write(p.fenChar);
        }
      }
      if (empty > 0) sb.write(empty);
      if (rank > 0) sb.write('/');
    }
    // Castling rights are kept only where king and rook stand on home squares.
    return '$sb ${_turn == Side.white ? 'w' : 'b'} KQkq - 0 1';
  }

  (Position?, String?) _position() {
    try {
      return (Position.fromFen(_fen), null);
    } on FormatException catch (e) {
      return (null, e.message);
    }
  }

  void _tap(String sq) {
    final i = Square.parse(sq)!;
    setState(() {
      _verdict = null;
      final brush = _brush;
      if (brush == null || _board[i] == brush) {
        _board[i] = null;
      } else {
        if (brush.role == Role.king) {
          final old = _board.indexWhere((p) => p == brush);
          if (old >= 0) _board[old] = null; // one king per side
        }
        _board[i] = brush;
      }
    });
  }

  Future<void> _flag(Position pos, Side side) async {
    if (!await ensureProAccess(context, ref, ProFeature.flagFall)) return;
    setState(() {
      _flagged = side;
      _verdict = checkFlagFall(pos, side);
    });
    revealAfterFrame(_resultKey);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final palette = ref.watch(settingsProvider).palette;
    final (pos, error) = _position();
    final v = _verdict;

    Widget brushButton(Piece? p) {
      final selected = _brush == p;
      return InkWell(
        borderRadius: BorderRadius.circular(ArbiterRadii.sm),
        onTap: () => setState(() => _brush = p),
        child: Container(
          width: 40,
          height: 40,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: selected ? c.accentPrimaryMuted : c.surfaceInset,
            borderRadius: BorderRadius.circular(ArbiterRadii.sm),
            border: Border.all(color: selected ? c.accentPrimary : c.surfaceElevated),
          ),
          child: p == null
              ? Icon(Icons.backspace_outlined, color: c.contentSecondary, size: 20)
              : SvgPicture.asset(
                  'assets/pieces/${p.side == Side.white ? 'w' : 'b'}${p.role.fenChar.toUpperCase()}.svg'),
        ),
      );
    }

    const roles = [Role.king, Role.queen, Role.rook, Role.bishop, Role.knight, Role.pawn];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tahtadaki konum'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => v == 'clear'
                ? _clear()
                : setState(() => _load(Position.startFen)),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'clear', child: Text('Tahtayı boşalt')),
              PopupMenuItem(value: 'start', child: Text('Başlangıç konumu')),
            ],
          ),
        ],
      ),
      body: Constrained(
        child: ListView(
          padding: const EdgeInsets.all(ArbiterSpacing.s3),
          children: [
            Text(
              'Karne olmadan (ör. yıldırımda) tahtadaki konumu kurun: taşı seçip '
              'kareye dokunun; aynı taşa tekrar dokunmak kaldırır.',
              style: TextStyle(color: c.contentSecondary),
            ),
            const SizedBox(height: ArbiterSpacing.s3),
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: (MediaQuery.sizeOf(context).height * 0.42).clamp(260.0, 440.0)),
                child: ChessBoard(
                  fen: _fen,
                  palette: palette,
                  onSquareTap: _tap,
                  checkSquare: pos != null && pos.isCheck
                      ? Square.name(pos.kingSquare(pos.turn))
                      : null,
                ),
              ),
            ),
            const SizedBox(height: ArbiterSpacing.s3),
            for (final side in Side.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Wrap(
                  spacing: 6,
                  children: [for (final r in roles) brushButton(Piece(side, r))],
                ),
              ),
            Row(
              children: [
                brushButton(null),
                const SizedBox(width: ArbiterSpacing.s3),
                Expanded(
                  child: SegmentedButton<Side>(
                    segments: const [
                      ButtonSegment(value: Side.white, label: Text('Sıra Beyaz')),
                      ButtonSegment(value: Side.black, label: Text('Sıra Siyah')),
                    ],
                    selected: {_turn},
                    onSelectionChanged: (s) => setState(() {
                      _turn = s.first;
                      _verdict = null;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ArbiterSpacing.s4),
            if (pos == null)
              DeskCard(
                color: c.feedbackWarning.withAlpha(20),
                borderColor: c.feedbackWarning.withAlpha(100),
                child: Text('Konum geçersiz: $error',
                    style: TextStyle(color: c.contentPrimary)),
              )
            else ...[
              _StatusCard(pos: pos),
              const SizedBox(height: ArbiterSpacing.s3),
              const SectionLabel('Bayrak düştü (6.9)'),
              Row(
                children: [
                  for (final side in Side.values) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _flag(pos, side),
                        icon: const Icon(Icons.timer_off_outlined),
                        label: Text('${side.trName}\'ın süresi bitti'),
                      ),
                    ),
                    if (side == Side.white) const SizedBox(width: ArbiterSpacing.s2),
                  ],
                ],
              ),
              if (v != null) ...[
                const SizedBox(height: ArbiterSpacing.s3),
                VerdictCard(
                  key: _resultKey,
                  ok: v.result != '?',
                  neutral: v.result == '?' || v.result == '1/2-1/2',
                  headline: v.headline,
                  subtitle: '${_flagged!.trName} süre aşımı · '
                      '${v.result == '?' ? 'sonuç hakem değerlendirmesine bağlı' : 'Sonuç: ${v.result}'}',
                  children: [for (final d in v.details) Bullet(d), ArticleChips(v.articles)],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.pos});
  final Position pos;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final dead = isDeadByMaterial(pos);
    final lines = <String>[
      if (pos.isCheckmate) '${pos.turn.trName} mat oldu (5.1.1).',
      if (pos.isStalemate) 'Pat: ${pos.turn.trName} tarafının yasal hamlesi yok (5.2.1).',
      if (!pos.isCheckmate && !pos.isStalemate && pos.isCheck)
        '${pos.turn.trName} şah altında.',
      for (final s in Side.values) mateAbilityTr(canCheckmate(pos, s), s),
    ];
    return VerdictCard(
      ok: !dead,
      neutral: !dead,
      headline: dead
          ? 'Ölü konum: oyun berabere biter (5.2.2)'
          : pos.isCheckmate || pos.isStalemate
              ? 'Oyun bitmiş durumda'
              : 'Konum değerlendirmesi',
      children: [
        for (final l in lines) Bullet(l),
        Text(
          'Malzemeye dayalıdır; kilitli piyon yapılarında sonucu hakem belirler.',
          style: TextStyle(color: c.contentTertiary, fontSize: ArbiterFontSize.labelSm),
        ),
        const SizedBox(height: ArbiterSpacing.s2),
        const ArticleChips([Fide.a5_2_2, Fide.a6_9, Fide.a7_5_5]),
      ],
    );
  }
}
