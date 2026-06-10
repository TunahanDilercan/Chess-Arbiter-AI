import 'package:flutter/material.dart';

// ── Public widget ─────────────────────────────────────────────────────────────

/// Renders an 8×8 chess board from a FEN string.
///
/// [fen]           — position string (full FEN or position part only).
/// [lastMoveFrom]  — square to highlight as move origin (e.g. `"e2"`).
/// [lastMoveTo]    — square to highlight as move destination.
/// [errorSquare]   — square to highlight in red (illegal / OCR failure).
/// [onSquareTap]   — called with algebraic square name when tapped.
class ChessBoard extends StatelessWidget {
  final String fen;
  final String? lastMoveFrom;
  final String? lastMoveTo;
  final String? errorSquare;
  final ValueChanged<String>? onSquareTap;

  const ChessBoard({
    super.key,
    required this.fen,
    this.lastMoveFrom,
    this.lastMoveTo,
    this.errorSquare,
    this.onSquareTap,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth;
          final squareSize = size / 8;
          final pieces = _parseFen(fen);

          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(120),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: GestureDetector(
                onTapUp: onSquareTap == null
                    ? null
                    : (details) {
                        final col =
                            (details.localPosition.dx / squareSize).floor();
                        final row =
                            (details.localPosition.dy / squareSize).floor();
                        if (col >= 0 && col < 8 && row >= 0 && row < 8) {
                          final file =
                              String.fromCharCode('a'.codeUnitAt(0) + col);
                          final rank = (8 - row).toString();
                          onSquareTap!('$file$rank');
                        }
                      },
                child: CustomPaint(
                  size: Size(size, size),
                  painter: _BoardPainter(
                    pieces: pieces,
                    squareSize: squareSize,
                    lastMoveFrom: lastMoveFrom,
                    lastMoveTo: lastMoveTo,
                    errorSquare: errorSquare,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
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

// ── Painter ───────────────────────────────────────────────────────────────────

class _BoardPainter extends CustomPainter {
  final Map<String, String> pieces;
  final double squareSize;
  final String? lastMoveFrom;
  final String? lastMoveTo;
  final String? errorSquare;

  static const _lightSquare = Color(0xFFF0D9B5);
  static const _darkSquare = Color(0xFFB58863);
  // Lichess-style last-move highlight (soft green-yellow overlay).
  static const _highlightColor = Color(0x669BC700);
  static const _errorColor = Color(0x88E84040);

  static const _whiteFill = Color(0xFFF8F8F2);
  static const _whiteOutline = Color(0xFF3C3A33);
  static const _blackFill = Color(0xFF31302C);
  static const _blackOutline = Color(0xFF8F8D86);

  // Both colours use the FILLED glyph set; colour is applied via paint.
  // Hollow white glyphs (♔♕…) render thin and toy-like — filled + outline
  // is how chess apps without SVG piece sets get a professional look.
  static const _unicodePieces = {
    'K': '♚', 'Q': '♛', 'R': '♜', 'B': '♝', 'N': '♞', 'P': '♟',
    'k': '♚', 'q': '♛', 'r': '♜', 'b': '♝', 'n': '♞', 'p': '♟',
  };

  const _BoardPainter({
    required this.pieces,
    required this.squareSize,
    this.lastMoveFrom,
    this.lastMoveTo,
    this.errorSquare,
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
          Paint()..color = isLight ? _lightSquare : _darkSquare,
        );

        final file = String.fromCharCode('a'.codeUnitAt(0) + col);
        final rank = (8 - row).toString();
        final square = '$file$rank';

        // Highlight last move
        if (square == lastMoveFrom || square == lastMoveTo) {
          canvas.drawRect(rect, Paint()..color = _highlightColor);
        }

        // Highlight error square
        if (square == errorSquare) {
          canvas.drawRect(rect, Paint()..color = _errorColor);
        }

        // Draw piece
        final piece = pieces[square];
        if (piece != null) {
          _drawPiece(canvas, piece, rect);
        }

        // Rank label on left column
        if (col == 0) {
          _drawLabel(canvas, rank, Offset(rect.left + 2, rect.top + 2),
              isLight ? _darkSquare : _lightSquare, squareSize * 0.22);
        }
        // File label on bottom row
        if (row == 7) {
          _drawLabel(
            canvas,
            file,
            Offset(rect.right - squareSize * 0.25, rect.bottom - squareSize * 0.28),
            isLight ? _darkSquare : _lightSquare,
            squareSize * 0.22,
          );
        }
      }
    }
  }

  void _drawPiece(Canvas canvas, String piece, Rect square) {
    final unicode = _unicodePieces[piece] ?? piece;
    final isWhite = piece == piece.toUpperCase();
    final fill = isWhite ? _whiteFill : _blackFill;
    final outline = isWhite ? _whiteOutline : _blackOutline;
    final fontSize = squareSize * 0.78;

    // Drop shadow grounds the piece on the square.
    final fillStyle = TextStyle(
      fontSize: fontSize,
      color: fill,
      shadows: [
        Shadow(
          color: Colors.black.withAlpha(110),
          blurRadius: squareSize * 0.06,
          offset: Offset(0, squareSize * 0.035),
        ),
      ],
    );
    final fillPainter = TextPainter(
      text: TextSpan(text: unicode, style: fillStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final origin = Offset(
      square.left + (square.width - fillPainter.width) / 2,
      square.top + (square.height - fillPainter.height) / 2,
    );
    fillPainter.paint(canvas, origin);

    // Outline pass on top keeps white pieces readable on light squares
    // and gives black pieces definition on dark squares.
    final outlinePainter = TextPainter(
      text: TextSpan(
        text: unicode,
        style: TextStyle(
          fontSize: fontSize,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = squareSize * (isWhite ? 0.035 : 0.025)
            ..color = outline,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    outlinePainter.paint(canvas, origin);
  }

  void _drawLabel(
      Canvas canvas, String text, Offset position, Color color, double size) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, position);
  }

  @override
  bool shouldRepaint(_BoardPainter oldDelegate) {
    return oldDelegate.pieces != pieces ||
        oldDelegate.lastMoveFrom != lastMoveFrom ||
        oldDelegate.lastMoveTo != lastMoveTo ||
        oldDelegate.errorSquare != errorSquare;
  }
}
