import 'types.dart';

/// Castling-right bits.
abstract final class CastlingBits {
  static const int whiteKing = 1;
  static const int whiteQueen = 2;
  static const int blackKing = 4;
  static const int blackQueen = 8;
}

const _knightSteps = [
  (1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2),
];
const _kingSteps = [
  (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1),
];
const _rookDirs = [(1, 0), (-1, 0), (0, 1), (0, -1)];
const _bishopDirs = [(1, 1), (1, -1), (-1, 1), (-1, -1)];
const _promotionRoles = [Role.queen, Role.rook, Role.bishop, Role.knight];

int? _offset(int sq, int df, int dr) {
  final f = Square.file(sq) + df;
  final r = Square.rank(sq) + dr;
  if (f < 0 || f > 7 || r < 0 || r > 7) return null;
  return Square.at(f, r);
}

// Precomputed geometry: target squares per origin, so the hot loops below do
// no bounds arithmetic, record destructuring or allocation.
List<List<int>> _stepTable(List<(int, int)> steps) => List.unmodifiable([
      for (var sq = 0; sq < 64; sq++)
        List<int>.unmodifiable([
          for (final (df, dr) in steps) ?_offset(sq, df, dr),
        ]),
    ]);

/// _rayTable(dirs)[sq][d] = squares from [sq] outward in direction d.
List<List<List<int>>> _rayTable(List<(int, int)> dirs) => List.unmodifiable([
      for (var sq = 0; sq < 64; sq++)
        List<List<int>>.unmodifiable([
          for (final (df, dr) in dirs)
            List<int>.unmodifiable(() sync* {
              var t = _offset(sq, df, dr);
              while (t != null) {
                yield t;
                t = _offset(t, df, dr);
              }
            }()),
        ]),
    ]);

final _knightTargets = _stepTable(_knightSteps);
final _kingTargets = _stepTable(_kingSteps);
final _rookRays = _rayTable(_rookDirs);
final _bishopRays = _rayTable(_bishopDirs);

/// Squares from which a pawn of [by] attacks the indexed square.
final _whitePawnAttackers = _stepTable(const [(-1, -1), (1, -1)]);
final _blackPawnAttackers = _stepTable(const [(-1, 1), (1, 1)]);

bool _attacked(List<Piece?> board, int sq, Side by) {
  for (final s in by == Side.white ? _whitePawnAttackers[sq] : _blackPawnAttackers[sq]) {
    final p = board[s];
    if (p != null && p.side == by && p.role == Role.pawn) return true;
  }
  for (final s in _knightTargets[sq]) {
    final p = board[s];
    if (p != null && p.side == by && p.role == Role.knight) return true;
  }
  for (final s in _kingTargets[sq]) {
    final p = board[s];
    if (p != null && p.side == by && p.role == Role.king) return true;
  }
  for (final ray in _rookRays[sq]) {
    for (final s in ray) {
      final p = board[s];
      if (p == null) continue;
      if (p.side == by && (p.role == Role.rook || p.role == Role.queen)) return true;
      break;
    }
  }
  for (final ray in _bishopRays[sq]) {
    for (final s in ray) {
      final p = board[s];
      if (p == null) continue;
      if (p.side == by && (p.role == Role.bishop || p.role == Role.queen)) return true;
      break;
    }
  }
  return false;
}

/// Immutable chess position (standard chess only).
class Position {
  Position._(
    this._board,
    this.turn,
    this.castling,
    this.epSquare,
    this.halfmoves,
    this.fullmoves,
  );

  static const String startFen =
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

  factory Position.initial() => Position.fromFen(startFen);

  /// Parses a FEN string. Throws [FormatException] on malformed input.
  factory Position.fromFen(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.length > 6) {
      throw FormatException('FEN alan sayısı hatalı', fen);
    }
    final rows = parts[0].split('/');
    if (rows.length != 8) {
      throw FormatException('FEN 8 sıra içermeli', fen);
    }
    final board = List<Piece?>.filled(64, null);
    for (var i = 0; i < 8; i++) {
      final rank = 7 - i;
      var file = 0;
      for (final ch in rows[i].split('')) {
        final n = int.tryParse(ch);
        if (n != null) {
          if (n < 1 || n > 8) throw FormatException('FEN boşluk sayısı', fen);
          file += n;
        } else {
          final p = Piece.fromFenChar(ch);
          if (p == null || file > 7) {
            throw FormatException('FEN taş karakteri hatalı: $ch', fen);
          }
          board[Square.at(file, rank)] = p;
          file++;
        }
        if (file > 8) throw FormatException('FEN sırası 8 kareyi aşıyor', fen);
      }
      if (file != 8) throw FormatException('FEN sırası 8 kare değil', fen);
    }
    for (final side in Side.values) {
      final kings =
          board.where((p) => p == Piece(side, Role.king)).length;
      if (kings != 1) {
        throw FormatException('Her tarafın tam bir şahı olmalı', fen);
      }
    }
    for (var f = 0; f < 8; f++) {
      final a = board[f];
      final b = board[56 + f];
      if ((a?.role == Role.pawn) || (b?.role == Role.pawn)) {
        throw FormatException('1. veya 8. sırada piyon olamaz', fen);
      }
    }

    final turnStr = parts.length > 1 ? parts[1] : 'w';
    if (turnStr != 'w' && turnStr != 'b') {
      throw FormatException('Sıra w veya b olmalı', fen);
    }
    final turn = turnStr == 'w' ? Side.white : Side.black;

    var castling = 0;
    final castStr = parts.length > 2 ? parts[2] : '-';
    if (castStr != '-') {
      for (final ch in castStr.split('')) {
        castling |= switch (ch) {
          'K' => CastlingBits.whiteKing,
          'Q' => CastlingBits.whiteQueen,
          'k' => CastlingBits.blackKing,
          'q' => CastlingBits.blackQueen,
          _ => throw FormatException('Rok hakkı hatalı: $ch', fen),
        };
      }
    }
    castling = _sanitizeCastling(board, castling);

    int? ep;
    final epStr = parts.length > 3 ? parts[3] : '-';
    if (epStr != '-') {
      ep = Square.parse(epStr);
      if (ep == null) throw FormatException('Geçerken alma karesi hatalı', fen);
      final expectedRank = turn == Side.white ? 5 : 2;
      if (Square.rank(ep) != expectedRank) ep = null;
    }
    final half = parts.length > 4 ? int.tryParse(parts[4]) : 0;
    final full = parts.length > 5 ? int.tryParse(parts[5]) : 1;
    if (half == null || half < 0 || full == null || full < 1) {
      throw FormatException('Hamle sayaçları hatalı', fen);
    }
    final pos = Position._(List.unmodifiable(board), turn, castling, ep, half,
        full);
    if (pos.isAttacked(pos.kingSquare(turn.opposite), turn)) {
      throw FormatException('Sırası olmayan tarafın şahı şah altında', fen);
    }
    return pos;
  }

  static int _sanitizeCastling(List<Piece?> board, int rights) {
    var r = rights;
    bool has(int sq, Piece p) => board[sq] == p;
    const wk = Piece(Side.white, Role.king);
    const wr = Piece(Side.white, Role.rook);
    const bk = Piece(Side.black, Role.king);
    const br = Piece(Side.black, Role.rook);
    if (!has(4, wk)) r &= ~(CastlingBits.whiteKing | CastlingBits.whiteQueen);
    if (!has(7, wr)) r &= ~CastlingBits.whiteKing;
    if (!has(0, wr)) r &= ~CastlingBits.whiteQueen;
    if (!has(60, bk)) r &= ~(CastlingBits.blackKing | CastlingBits.blackQueen);
    if (!has(63, br)) r &= ~CastlingBits.blackKing;
    if (!has(56, br)) r &= ~CastlingBits.blackQueen;
    return r;
  }

  final List<Piece?> _board;
  final Side turn;
  final int castling;

  /// En passant target square after a double pawn push (may not be capturable).
  final int? epSquare;
  final int halfmoves;
  final int fullmoves;

  Piece? pieceAt(int sq) => _board[sq];

  Iterable<(int, Piece)> get pieces sync* {
    for (var sq = 0; sq < 64; sq++) {
      final p = _board[sq];
      if (p != null) yield (sq, p);
    }
  }

  int kingSquare(Side side) => side == Side.white ? _whiteKing : _blackKing;

  late final int _whiteKing = _findKing(Side.white);
  late final int _blackKing = _findKing(Side.black);

  int _findKing(Side side) {
    for (var sq = 0; sq < 64; sq++) {
      final p = _board[sq];
      if (p != null && p.role == Role.king && p.side == side) return sq;
    }
    return -1;
  }

  bool isAttacked(int sq, Side by) => _attacked(_board, sq, by);

  bool get isCheck => isAttacked(kingSquare(turn), turn.opposite);

  late final List<Move> legalMoves = _generateLegal();

  bool get isCheckmate => isCheck && legalMoves.isEmpty;
  bool get isStalemate => !isCheck && legalMoves.isEmpty;

  bool isLegal(Move m) => legalMoves.contains(m);

  bool isEnPassant(Move m) {
    final p = _board[m.from];
    return p != null &&
        p.role == Role.pawn &&
        m.to == epSquare &&
        Square.file(m.from) != Square.file(m.to) &&
        _board[m.to] == null;
  }

  bool isCapture(Move m) => _board[m.to] != null || isEnPassant(m);

  bool isCastle(Move m) {
    final p = _board[m.from];
    return p != null &&
        p.role == Role.king &&
        (Square.file(m.from) - Square.file(m.to)).abs() == 2;
  }

  /// Legal en passant target, or null (FIDE 9.2.2.1 / FEN "legal" convention).
  late final int? legalEpSquare = epSquare != null &&
          legalMoves.any((m) => m.to == epSquare && isEnPassant(m))
      ? epSquare
      : null;

  late final String placementFen = _buildPlacement();

  String _buildPlacement() {
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
    return sb.toString();
  }

  String get castlingFen {
    final sb = StringBuffer();
    if (castling & CastlingBits.whiteKing != 0) sb.write('K');
    if (castling & CastlingBits.whiteQueen != 0) sb.write('Q');
    if (castling & CastlingBits.blackKing != 0) sb.write('k');
    if (castling & CastlingBits.blackQueen != 0) sb.write('q');
    return sb.isEmpty ? '-' : sb.toString();
  }

  String get fen {
    final ep = legalEpSquare;
    return '$placementFen ${turn == Side.white ? 'w' : 'b'} $castlingFen '
        '${ep == null ? '-' : Square.name(ep)} $halfmoves $fullmoves';
  }

  /// Identity of a position per FIDE 9.2.2: same side to move, same pieces on
  /// the same squares, same possible moves (castling rights + legal en passant).
  /// Move counters are deliberately excluded.
  late final String repetitionKey = '$placementFen ${turn == Side.white ? 'w' : 'b'} '
      '$castlingFen ${legalEpSquare == null ? '-' : Square.name(legalEpSquare!)}';

  /// Applies a legal move and returns the new position. The caller must ensure
  /// legality (e.g. via [legalMoves]); illegal input yields an invalid position.
  Position play(Move m) {
    if (_lastMove == m) return _lastChild!;
    final child = _play(m);
    _lastMove = m;
    _lastChild = child;
    return child;
  }

  Move? _lastMove;
  Position? _lastChild;

  Position _play(Move m) {
    final board = List<Piece?>.of(_board);
    final piece = board[m.from]!;
    final captured = board[m.to];
    final ep = isEnPassant(m);
    if (ep) {
      board[m.to + (turn == Side.white ? -8 : 8)] = null;
    }
    board[m.to] = m.promotion != null ? Piece(turn, m.promotion!) : piece;
    board[m.from] = null;
    if (piece.role == Role.king && (m.to - m.from).abs() == 2) {
      if (m.to > m.from) {
        board[m.from + 1] = board[m.from + 3];
        board[m.from + 3] = null;
      } else {
        board[m.from - 1] = board[m.from - 4];
        board[m.from - 4] = null;
      }
    }
    var rights = castling;
    if (piece.role == Role.king) {
      rights &= turn == Side.white
          ? ~(CastlingBits.whiteKing | CastlingBits.whiteQueen)
          : ~(CastlingBits.blackKing | CastlingBits.blackQueen);
    }
    for (final sq in [m.from, m.to]) {
      rights &= switch (sq) {
        0 => ~CastlingBits.whiteQueen,
        7 => ~CastlingBits.whiteKing,
        56 => ~CastlingBits.blackQueen,
        63 => ~CastlingBits.blackKing,
        _ => ~0,
      };
    }
    final isPawn = piece.role == Role.pawn;
    final newEp =
        isPawn && (m.to - m.from).abs() == 16 ? (m.from + m.to) ~/ 2 : null;
    return Position._(
      board, // private and never mutated after construction
      turn.opposite,
      rights,
      newEp,
      isPawn || captured != null || ep ? 0 : halfmoves + 1,
      turn == Side.black ? fullmoves + 1 : fullmoves,
    );
  }

  /// Pseudo-legal moves for [piece] standing on [from] (own king safety ignored).
  List<Move> pseudoMovesFrom(int from) {
    final piece = _board[from];
    if (piece == null || piece.side != turn) return const [];
    final out = <Move>[];
    switch (piece.role) {
      case Role.pawn:
        _pawnMoves(from, out);
      case Role.knight:
        _stepMoves(from, _knightTargets, out);
      case Role.bishop:
        _slideMoves(from, _bishopRays, out);
      case Role.rook:
        _slideMoves(from, _rookRays, out);
      case Role.queen:
        _slideMoves(from, _rookRays, out);
        _slideMoves(from, _bishopRays, out);
      case Role.king:
        _stepMoves(from, _kingTargets, out);
        _castleMoves(from, out);
    }
    return out;
  }

  /// True when a pseudo-legal move would leave the mover's own king attacked.
  bool leavesKingInCheck(Move m) => _exposesKing(List<Piece?>.of(_board), m);

  /// Make/test/unmake on [scratch] (a copy of the board); restores it exactly.
  bool _exposesKing(List<Piece?> scratch, Move m) {
    final piece = scratch[m.from]!;
    final captured = scratch[m.to];
    final ep = isEnPassant(m);
    final epSq = ep ? m.to + (turn == Side.white ? -8 : 8) : -1;
    final epPawn = ep ? scratch[epSq] : null;
    if (ep) scratch[epSq] = null;
    scratch[m.to] = piece; // promotion role is irrelevant for king safety
    scratch[m.from] = null;
    // Castling: the rook move cannot change whether the king is attacked
    // (the transit squares are checked in _castleMoves).
    final kingSq = piece.role == Role.king ? m.to : kingSquare(turn);
    final exposed = _attacked(scratch, kingSq, turn.opposite);
    scratch[m.from] = piece;
    scratch[m.to] = captured;
    if (ep) scratch[epSq] = epPawn;
    return exposed;
  }

  List<Move> _generateLegal() {
    final out = <Move>[];
    final scratch = List<Piece?>.of(_board);
    // Fast path: when not in check, a move of an unpinned non-king piece
    // (other than en passant) can never expose the own king, so only king
    // moves, pinned pieces, en passant and check evasions are verified.
    final inCheck = isCheck;
    final pinned = inCheck ? null : _pinned();
    for (var sq = 0; sq < 64; sq++) {
      final p = _board[sq];
      if (p == null || p.side != turn) continue;
      final verify = inCheck || p.role == Role.king || pinned![sq];
      for (final m in pseudoMovesFrom(sq)) {
        if ((verify || isEnPassant(m)) && _exposesKing(scratch, m)) continue;
        out.add(m);
      }
    }
    return List.unmodifiable(out);
  }

  /// Squares of the mover's pieces pinned to their king. (A list, not a bit
  /// mask: web builds only have 32-bit shifts.)
  List<bool> _pinned() {
    final king = kingSquare(turn);
    final mask = List<bool>.filled(64, false);
    void scan(List<List<int>> rays, Role slider) {
      for (final ray in rays) {
        int? own;
        for (final s in ray) {
          final p = _board[s];
          if (p == null) continue;
          if (own == null) {
            if (p.side != turn) break;
            own = s;
          } else {
            if (p.side != turn && (p.role == slider || p.role == Role.queen)) {
              mask[own] = true;
            }
            break;
          }
        }
      }
    }

    scan(_rookRays[king], Role.rook);
    scan(_bishopRays[king], Role.bishop);
    return mask;
  }

  void _pawnMoves(int from, List<Move> out) {
    final dr = turn == Side.white ? 1 : -1;
    final startRank = turn == Side.white ? 1 : 6;
    final promoRank = turn == Side.white ? 7 : 0;
    void add(int to) {
      if (Square.rank(to) == promoRank) {
        for (final r in _promotionRoles) {
          out.add(Move(from, to, promotion: r));
        }
      } else {
        out.add(Move(from, to));
      }
    }

    final one = _offset(from, 0, dr);
    if (one != null && _board[one] == null) {
      add(one);
      if (Square.rank(from) == startRank) {
        final two = _offset(from, 0, 2 * dr);
        if (two != null && _board[two] == null) out.add(Move(from, two));
      }
    }
    for (final df in const [-1, 1]) {
      final to = _offset(from, df, dr);
      if (to == null) continue;
      final target = _board[to];
      if ((target != null && target.side != turn) ||
          (target == null && to == epSquare)) {
        add(to);
      }
    }
  }

  void _stepMoves(int from, List<List<int>> table, List<Move> out) {
    for (final to in table[from]) {
      final t = _board[to];
      if (t == null || t.side != turn) out.add(Move(from, to));
    }
  }

  void _slideMoves(int from, List<List<List<int>>> rays, List<Move> out) {
    for (final ray in rays[from]) {
      for (final to in ray) {
        final t = _board[to];
        if (t == null) {
          out.add(Move(from, to));
        } else {
          if (t.side != turn) out.add(Move(from, to));
          break;
        }
      }
    }
  }

  void _castleMoves(int from, List<Move> out) {
    final home = turn == Side.white ? 4 : 60;
    if (from != home) return;
    final enemy = turn.opposite;
    if (isAttacked(home, enemy)) return;
    final kBit =
        turn == Side.white ? CastlingBits.whiteKing : CastlingBits.blackKing;
    final qBit =
        turn == Side.white ? CastlingBits.whiteQueen : CastlingBits.blackQueen;
    if (castling & kBit != 0 &&
        _board[home + 1] == null &&
        _board[home + 2] == null &&
        _board[home + 3] == Piece(turn, Role.rook) &&
        !isAttacked(home + 1, enemy) &&
        !isAttacked(home + 2, enemy)) {
      out.add(Move(home, home + 2));
    }
    if (castling & qBit != 0 &&
        _board[home - 1] == null &&
        _board[home - 2] == null &&
        _board[home - 3] == null &&
        _board[home - 4] == Piece(turn, Role.rook) &&
        !isAttacked(home - 1, enemy) &&
        !isAttacked(home - 2, enemy)) {
      out.add(Move(home, home - 2));
    }
  }
}
