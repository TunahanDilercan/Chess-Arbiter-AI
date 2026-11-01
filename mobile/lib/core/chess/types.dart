/// Basic chess types. Pure Dart — no Flutter imports anywhere under lib/core.
library;

enum Side {
  white,
  black;

  Side get opposite => this == Side.white ? Side.black : Side.white;

  String get trName => this == Side.white ? 'Beyaz' : 'Siyah';
}

enum Role {
  pawn('p', ''),
  knight('n', 'N'),
  bishop('b', 'B'),
  rook('r', 'R'),
  queen('q', 'Q'),
  king('k', 'K');

  const Role(this.fenChar, this.sanLetter);

  final String fenChar;
  final String sanLetter;

  static Role? fromSanLetter(String letter) {
    for (final r in Role.values) {
      if (r != Role.pawn && r.sanLetter == letter) return r;
    }
    return null;
  }
}

class Piece {
  const Piece(this.side, this.role);

  final Side side;
  final Role role;

  /// FEN letter: uppercase for white.
  String get fenChar =>
      side == Side.white ? role.fenChar.toUpperCase() : role.fenChar;

  static Piece? fromFenChar(String c) {
    final lower = c.toLowerCase();
    for (final r in Role.values) {
      if (r.fenChar == lower) {
        return Piece(c == lower ? Side.black : Side.white, r);
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is Piece && other.side == side && other.role == role;

  @override
  int get hashCode => side.index * 8 + role.index;

  @override
  String toString() => fenChar;
}

/// Squares are 0..63 with a1 = 0, b1 = 1 … h8 = 63.
abstract final class Square {
  static int file(int sq) => sq & 7;
  static int rank(int sq) => sq >> 3;
  static int at(int file, int rank) => rank * 8 + file;

  static String name(int sq) =>
      '${String.fromCharCode(97 + file(sq))}${rank(sq) + 1}';

  static int? parse(String s) {
    if (s.length != 2) return null;
    final f = s.codeUnitAt(0) - 97;
    final r = s.codeUnitAt(1) - 49;
    if (f < 0 || f > 7 || r < 0 || r > 7) return null;
    return at(f, r);
  }

  /// True for light squares (a1 is dark).
  static bool isLight(int sq) => (file(sq) + rank(sq)).isOdd;
}

class Move {
  const Move(this.from, this.to, {this.promotion});

  final int from;
  final int to;
  final Role? promotion;

  String get uci =>
      '${Square.name(from)}${Square.name(to)}${promotion?.fenChar ?? ''}';

  static Move? fromUci(String uci) {
    if (uci.length < 4 || uci.length > 5) return null;
    final from = Square.parse(uci.substring(0, 2));
    final to = Square.parse(uci.substring(2, 4));
    if (from == null || to == null) return null;
    Role? promo;
    if (uci.length == 5) {
      promo = Piece.fromFenChar(uci[4].toLowerCase())?.role;
      if (promo == null || promo == Role.pawn || promo == Role.king) {
        return null;
      }
    }
    return Move(from, to, promotion: promo);
  }

  @override
  bool operator ==(Object other) =>
      other is Move &&
      other.from == from &&
      other.to == to &&
      other.promotion == promotion;

  @override
  int get hashCode => from * 64 * 8 + to * 8 + (promotion?.index ?? 7);

  @override
  String toString() => uci;
}
