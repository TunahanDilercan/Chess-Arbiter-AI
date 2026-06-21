import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/arbiter_tokens.dart';

class _PaletteColors {
  const _PaletteColors(this.light, this.dark, this.coord);
  final Color light;
  final Color dark;
  final Color coord;
}

_PaletteColors _paletteColors(BoardPalette p) {
  switch (p) {
    case BoardPalette.wood:
      return const _PaletteColors(ArbiterPalette.boardWoodSqLight,
          ArbiterPalette.boardWoodSqDark, ArbiterPalette.boardWoodCoordinates);
    case BoardPalette.slate:
      return const _PaletteColors(ArbiterPalette.boardSlateSqLight,
          ArbiterPalette.boardSlateSqDark, ArbiterPalette.boardSlateCoordinates);
    case BoardPalette.mono:
      return const _PaletteColors(ArbiterPalette.boardMonoSqLight,
          ArbiterPalette.boardMonoSqDark, ArbiterPalette.boardMonoCoordinates);
    case BoardPalette.oled:
      return const _PaletteColors(ArbiterPalette.boardOledSqLight,
          ArbiterPalette.boardOledSqDark, ArbiterPalette.boardOledCoordinates);
  }
}

/// Renders an 8×8 chess board from a FEN string using the Cburnett SVG piece
/// set. Pure display — it never computes legality, checks or moves (the backend
/// is the sole chess authority; see CLAUDE.md). Pieces are drawn at 92 % of the
/// square width per the design charter.
///
/// [fen]           — position string (full FEN or position part only).
/// [lastMoveFrom]  — square highlighted as move origin (e.g. `"e2"`).
/// [lastMoveTo]    — square highlighted as move destination.
/// [errorSquare]   — square highlighted in danger (illegal / OCR failure).
/// [flipped]       — render from black's perspective.
/// [dimmed]        — fade the board (game-over banner state).
/// [onSquareTap]   — called with the algebraic square name when tapped.
class ChessBoard extends StatelessWidget {
  final String fen;
  final String? lastMoveFrom;
  final String? lastMoveTo;
  final String? errorSquare;
  final String? checkSquare;
  final bool flipped;
  final bool dimmed;
  final BoardPalette palette;
  final ValueChanged<String>? onSquareTap;

  const ChessBoard({
    super.key,
    required this.fen,
    this.lastMoveFrom,
    this.lastMoveTo,
    this.errorSquare,
    this.checkSquare,
    this.flipped = false,
    this.dimmed = false,
    this.palette = BoardPalette.wood,
    this.onSquareTap,
  });

  @override
  Widget build(BuildContext context) {
    final pieces = _parseFen(fen);
    final colors = _paletteColors(palette);

    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth;
          final squareSize = size / 8;

          final pieceWidgets = <Widget>[];
          pieces.forEach((square, piece) {
            final pos = _squarePos(square, flipped);
            if (pos == null) return;
            pieceWidgets.add(Positioned(
              left: pos.dx * squareSize,
              top: pos.dy * squareSize,
              width: squareSize,
              height: squareSize,
              child: Center(
                child: SvgPicture.asset(
                  _assetFor(piece),
                  width: squareSize * 0.92,
                  height: squareSize * 0.92,
                ),
              ),
            ));
          });

          Widget board = ClipRRect(
            borderRadius: BorderRadius.circular(ArbiterRadii.sm),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _BoardPainter(
                      squareSize: squareSize,
                      flipped: flipped,
                      colors: colors,
                      lastMoveFrom: lastMoveFrom,
                      lastMoveTo: lastMoveTo,
                      errorSquare: errorSquare,
                      checkSquare: checkSquare,
                    ),
                  ),
                ),
                ...pieceWidgets,
              ],
            ),
          );

          if (dimmed) {
            board = Opacity(opacity: 0.6, child: board);
          }

          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ArbiterRadii.sm),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(120),
                  blurRadius: 24,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: onSquareTap == null
                ? board
                : GestureDetector(
                    onTapUp: (details) {
                      final col = (details.localPosition.dx / squareSize).floor();
                      final row = (details.localPosition.dy / squareSize).floor();
                      if (col < 0 || col > 7 || row < 0 || row > 7) return;
                      final fileIdx = flipped ? 7 - col : col;
                      final rankIdx = flipped ? row + 1 : 8 - row;
                      final file = String.fromCharCode('a'.codeUnitAt(0) + fileIdx);
                      onSquareTap!('$file$rankIdx');
                    },
                    child: board,
                  ),
          );
        },
      ),
    );
  }

  /// Asset path for a FEN piece char: 'K' → wK.svg, 'n' → bN.svg.
  static String _assetFor(String piece) {
    final color = piece == piece.toUpperCase() ? 'w' : 'b';
    return 'assets/pieces/$color${piece.toUpperCase()}.svg';
  }

  /// Square name ("e4") → grid (col,row) offset, honoring board flip.
  static Offset? _squarePos(String square, bool flipped) {
    if (square.length < 2) return null;
    final fileIdx = square.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final rank = int.tryParse(square.substring(1));
    if (fileIdx < 0 || fileIdx > 7 || rank == null || rank < 1 || rank > 8) {
      return null;
    }
    final col = flipped ? 7 - fileIdx : fileIdx;
    final row = flipped ? rank - 1 : 8 - rank;
    return Offset(col.toDouble(), row.toDouble());
  }

  /// Parse FEN position part into a map of square → piece char.
  static Map<String, String> _parseFen(String fen) {
    final positionPart = fen.split(' ').first;
    final rows = positionPart.split('/');
    final result = <String, String>{};
    for (var rankIdx = 0; rankIdx < rows.length && rankIdx < 8; rankIdx++) {
      var fileIdx = 0;
      for (final char in rows[rankIdx].split('')) {
        final empty = int.tryParse(char);
        if (empty != null) {
          fileIdx += empty;
        } else {
          final file = String.fromCharCode('a'.codeUnitAt(0) + fileIdx);
          final rank = (8 - rankIdx).toString();
          result['$file$rank'] = char;
          fileIdx++;
        }
      }
    }
    return result;
  }
}

class _BoardPainter extends CustomPainter {
  final double squareSize;
  final bool flipped;
  final _PaletteColors colors;
  final String? lastMoveFrom;
  final String? lastMoveTo;
  final String? errorSquare;
  final String? checkSquare;

  static const _lastMove = ArbiterPalette.highlightLastMove;
  static const _illegal = ArbiterPalette.highlightIllegal;
  static const _check = ArbiterPalette.highlightCheck;

  const _BoardPainter({
    required this.squareSize,
    required this.flipped,
    required this.colors,
    this.lastMoveFrom,
    this.lastMoveTo,
    this.errorSquare,
    this.checkSquare,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var row = 0; row < 8; row++) {
      for (var col = 0; col < 8; col++) {
        final rect = Rect.fromLTWH(
          col * squareSize,
          row * squareSize,
          squareSize,
          squareSize,
        );
        final isLight = (row + col) % 2 == 0;
        canvas.drawRect(
          rect,
          Paint()..color = isLight ? colors.light : colors.dark,
        );

        final fileIdx = flipped ? 7 - col : col;
        final rankIdx = flipped ? row + 1 : 8 - row;
        final file = String.fromCharCode('a'.codeUnitAt(0) + fileIdx);
        final square = '$file$rankIdx';

        if (square == lastMoveFrom || square == lastMoveTo) {
          canvas.drawRect(rect, Paint()..color = _lastMove);
        }
        if (square == errorSquare) {
          canvas.drawRect(rect, Paint()..color = _illegal);
        }
        if (square == checkSquare) {
          canvas.drawRect(rect, Paint()..color = _check);
        }

        // Rank labels down the left column, file labels along the bottom row.
        if (col == 0) {
          _drawLabel(canvas, '$rankIdx',
              Offset(rect.left + 3, rect.top + 2), squareSize * 0.20);
        }
        if (row == 7) {
          _drawLabel(
            canvas,
            file,
            Offset(rect.right - squareSize * 0.26, rect.bottom - squareSize * 0.26),
            squareSize * 0.20,
          );
        }
      }
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset position, double fontSize) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: ArbiterFontFamily.mono,
          fontSize: fontSize,
          color: colors.coord,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, position);
  }

  @override
  bool shouldRepaint(_BoardPainter oldDelegate) {
    return oldDelegate.squareSize != squareSize ||
        oldDelegate.flipped != flipped ||
        oldDelegate.colors != colors ||
        oldDelegate.lastMoveFrom != lastMoveFrom ||
        oldDelegate.lastMoveTo != lastMoveTo ||
        oldDelegate.errorSquare != errorSquare ||
        oldDelegate.checkSquare != checkSquare;
  }
}
