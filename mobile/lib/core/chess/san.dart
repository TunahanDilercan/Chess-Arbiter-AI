import 'position.dart';
import 'types.dart';

/// Canonical SAN for a legal move in [pos].
String toSan(Position pos, Move m) {
  final piece = pos.pieceAt(m.from)!;
  final sb = StringBuffer();
  if (pos.isCastle(m)) {
    sb.write(m.to > m.from ? 'O-O' : 'O-O-O');
  } else if (piece.role == Role.pawn) {
    if (pos.isCapture(m)) {
      sb
        ..write(Square.name(m.from)[0])
        ..write('x');
    }
    sb.write(Square.name(m.to));
    if (m.promotion != null) sb.write('=${m.promotion!.sanLetter}');
  } else {
    sb.write(piece.role.sanLetter);
    final rivals = pos.legalMoves.where((o) =>
        o.to == m.to &&
        o.from != m.from &&
        pos.pieceAt(o.from)?.role == piece.role);
    if (rivals.isNotEmpty) {
      final sameFile =
          rivals.any((o) => Square.file(o.from) == Square.file(m.from));
      final sameRank =
          rivals.any((o) => Square.rank(o.from) == Square.rank(m.from));
      if (!sameFile) {
        sb.write(Square.name(m.from)[0]);
      } else if (!sameRank) {
        sb.write(Square.name(m.from)[1]);
      } else {
        sb.write(Square.name(m.from));
      }
    }
    if (pos.isCapture(m)) sb.write('x');
    sb.write(Square.name(m.to));
  }
  final next = pos.play(m);
  if (next.isCheckmate) {
    sb.write('#');
  } else if (next.isCheck) {
    sb.write('+');
  }
  return sb.toString();
}

/// SAN without check/mate suffixes and capture markers, for loose comparison.
String bareSan(String san) => san.replaceAll(RegExp(r'[+#x:!?]'), '');

enum SanParseStatus {
  /// Parsed to exactly one legal move, notation fully consistent.
  exact,

  /// One legal move, but the written notation has a cosmetic slip (missing
  /// "+", wrong "x", over-disambiguation, …). Not an illegal move.
  notationWarning,

  /// The text fits more than one legal move — arbiter must decide.
  ambiguous,

  /// Syntactically a move, but no legal move matches it.
  illegal,

  /// Not recognisable as chess notation.
  unparseable,

  /// Empty / unknown cell on the scoresheet.
  empty,
}

class SanParse {
  const SanParse(this.status,
      {this.move, this.candidates = const [], this.warnings = const []});

  final SanParseStatus status;
  final Move? move;

  /// For [SanParseStatus.ambiguous]: all matching legal moves.
  final List<Move> candidates;
  final List<String> warnings;

  bool get isResolved =>
      status == SanParseStatus.exact ||
      status == SanParseStatus.notationWarning;
}

/// Syntactic description of a written move.
class _Spec {
  _Spec({
    this.role,
    this.fromFile,
    this.fromRank,
    this.fromSquare,
    this.to,
    this.promotion,
    this.capture = false,
    this.castle,
  });

  Role? role;
  int? fromFile;
  int? fromRank;
  int? fromSquare;
  int? to;
  Role? promotion;
  bool capture;

  /// 'K' king side, 'Q' queen side.
  String? castle;
}

final _reCastle = RegExp(r'^O-O(-O)?$');
final _reLong =
    RegExp(r'^([NBRQK])?([a-h][1-8])([-x:]?)([a-h][1-8])=?([NBRQnbrq])?$');
final _rePiece = RegExp(r'^([NBRQK])([a-h])?([1-8])?([x:]?)([a-h][1-8])$');
final _rePawn =
    RegExp(r'^([a-h])(?:([x:]?)([a-h])([1-8])|([1-8]))=?([NBRQnbrq])?$');

/// Strips annotation glyphs and suffixes. Returns (core, hasCheck, hasMate).
(String, bool, bool) _strip(String token) {
  var t = token.trim();
  t = t.replaceAll(RegExp(r'(e\.?p\.?)$'), '');
  t = t.replaceAll(RegExp(r'[!?]+$'), '');
  var mate = false;
  var check = false;
  if (t.endsWith('#') || t.endsWith('++')) {
    mate = true;
    t = t.replaceAll(RegExp(r'(#|\+\+)$'), '');
  } else if (t.endsWith('+')) {
    check = true;
    t = t.substring(0, t.length - 1);
  }
  return (t, check, mate);
}

_Spec? _parseSpec(String core) {
  if (_reCastle.hasMatch(core)) {
    return _Spec(castle: core == 'O-O' ? 'K' : 'Q', role: Role.king);
  }
  var m = _rePiece.firstMatch(core);
  if (m != null) {
    return _Spec(
      role: Role.fromSanLetter(m.group(1)!),
      fromFile: m.group(2) == null ? null : m.group(2)!.codeUnitAt(0) - 97,
      fromRank: m.group(3) == null ? null : int.parse(m.group(3)!) - 1,
      capture: m.group(4)!.isNotEmpty,
      to: Square.parse(m.group(5)!),
    );
  }
  m = _rePawn.firstMatch(core);
  if (m != null) {
    final file = m.group(1)!.codeUnitAt(0) - 97;
    final promo =
        m.group(6) == null ? null : Role.fromSanLetter(m.group(6)!.toUpperCase());
    if (m.group(5) != null) {
      return _Spec(
        role: Role.pawn,
        fromFile: file,
        to: Square.at(file, int.parse(m.group(5)!) - 1),
        promotion: promo,
      );
    }
    final toFile = m.group(3)!.codeUnitAt(0) - 97;
    return _Spec(
      role: Role.pawn,
      fromFile: file,
      capture: m.group(2)!.isNotEmpty,
      to: Square.at(toFile, int.parse(m.group(4)!) - 1),
      promotion: promo,
    );
  }
  m = _reLong.firstMatch(core);
  if (m != null) {
    return _Spec(
      role: m.group(1) == null ? null : Role.fromSanLetter(m.group(1)!),
      fromSquare: Square.parse(m.group(2)!),
      capture: m.group(3) == 'x' || m.group(3) == ':',
      to: Square.parse(m.group(4)!),
      promotion:
          m.group(5) == null ? null : Role.fromSanLetter(m.group(5)!.toUpperCase()),
    );
  }
  return null;
}

bool _matches(Position pos, Move mv, _Spec s) {
  final piece = pos.pieceAt(mv.from);
  if (piece == null) return false;
  if (s.castle != null) {
    return pos.isCastle(mv) &&
        (s.castle == 'K' ? mv.to > mv.from : mv.to < mv.from);
  }
  if (s.role != null && piece.role != s.role) return false;
  if (s.fromSquare != null && mv.from != s.fromSquare) return false;
  if (s.fromFile != null && Square.file(mv.from) != s.fromFile) return false;
  if (s.fromRank != null && Square.rank(mv.from) != s.fromRank) return false;
  if (mv.to != s.to) return false;
  // A king written as e1g1 / Kg1 is still castling; accept it.
  if (s.promotion != null && mv.promotion != s.promotion) return false;
  return true;
}

/// Parses a (normalized, English-letter) move token against [pos].
///
/// Tolerant of the slips commonly seen on handwritten scoresheets — missing or
/// wrong "+"/"#", missing/extra "x", unnecessary disambiguation, long algebraic
/// ("Ng1-f3", "e2e4") — but never guesses between two different legal moves.
SanParse parseMove(Position pos, String token) {
  final raw = token.trim();
  if (raw.isEmpty || raw == '?' || raw == '--' || raw == '…' || raw == '...') {
    return const SanParse(SanParseStatus.empty);
  }
  final (core, wroteCheck, wroteMate) = _strip(raw);
  final spec = _parseSpec(core);
  if (spec == null) return const SanParse(SanParseStatus.unparseable);

  final cands = pos.legalMoves.where((m) => _matches(pos, m, spec)).toList();
  if (cands.isEmpty) return const SanParse(SanParseStatus.illegal);

  if (cands.length > 1) {
    // Missing promotion piece or genuinely ambiguous disambiguation.
    return SanParse(SanParseStatus.ambiguous, candidates: cands);
  }

  final mv = cands.single;
  final warnings = <String>[];
  final next = pos.play(mv);
  if (next.isCheckmate && !wroteMate) {
    warnings.add('Mat işareti (#) yazılmamış');
  } else if (!next.isCheckmate && wroteMate) {
    warnings.add('"#" yazılmış ama hamle mat değil');
  } else if (next.isCheck && !next.isCheckmate && !wroteCheck) {
    warnings.add('Şah işareti (+) yazılmamış');
  } else if (!next.isCheck && wroteCheck) {
    warnings.add('"+" yazılmış ama hamle şah çekmiyor');
  }
  final isCap = pos.isCapture(mv);
  if (spec.castle == null) {
    if (spec.capture && !isCap) warnings.add('"x" yazılmış ama alma yok');
    if (!spec.capture && isCap && spec.fromSquare == null) {
      warnings.add('Alma işareti (x) yazılmamış');
    }
  }
  return SanParse(
    warnings.isEmpty ? SanParseStatus.exact : SanParseStatus.notationWarning,
    move: mv,
    warnings: warnings,
  );
}

/// Human-readable reasons (Turkish) why [token] is not legal in [pos].
List<String> explainIllegal(Position pos, String token) {
  final (core, _, _) = _strip(token.trim());
  final spec = _parseSpec(core);
  if (spec == null) return ['Hamle notasyonu tanınamadı.'];
  final side = pos.turn.trName;
  final reasons = <String>[];

  if (spec.castle != null) {
    final kSide = spec.castle == 'K';
    final home = pos.turn == Side.white ? 4 : 60;
    final bit = switch ((pos.turn, kSide)) {
      (Side.white, true) => CastlingBits.whiteKing,
      (Side.white, false) => CastlingBits.whiteQueen,
      (Side.black, true) => CastlingBits.blackKing,
      (Side.black, false) => CastlingBits.blackQueen,
    };
    if (pos.castling & bit == 0) {
      reasons.add('$side bu yöne rok hakkını kaybetmiş (şah veya kale daha '
          'önce oynamış).');
    } else if (pos.isCheck) {
      reasons.add('Şah çekilmişken rok yapılamaz (Madde 3.8.2.2).');
    } else {
      final path = kSide ? [home + 1, home + 2] : [home - 1, home - 2, home - 3];
      if (path.any((s) => pos.pieceAt(s) != null)) {
        reasons.add('Şah ile kale arasında taş var.');
      } else {
        final crossed = kSide ? [home + 1, home + 2] : [home - 1, home - 2];
        final attacked =
            crossed.where((s) => pos.isAttacked(s, pos.turn.opposite));
        if (attacked.isNotEmpty) {
          reasons.add('Şah tehdit altındaki ${attacked.map(Square.name).join(', ')} '
              'karesinden geçer veya oraya gider (Madde 3.8.2.2).');
        }
      }
    }
    if (reasons.isEmpty) reasons.add('Rok bu konumda yasal değil.');
    return reasons;
  }

  // Pseudo-legal matches that are rejected only because of king safety.
  final pseudo = <Move>[];
  for (final (sq, p) in pos.pieces) {
    if (p.side != pos.turn) continue;
    pseudo.addAll(pos.pseudoMovesFrom(sq).where((m) => _matches(pos, m, spec)));
  }
  if (pseudo.isNotEmpty) {
    if (pos.isCheck) {
      reasons.add('$side şah altında; bu hamle şahı kurtarmıyor '
          '(Madde 3.9).');
    } else {
      reasons.add('Bu hamle $side şahını şah altında bırakır (açmazdaki taş) '
          '(Madde 3.9).');
    }
    return reasons;
  }

  if (spec.role == Role.pawn && spec.to != null) {
    final rank = Square.rank(spec.to!);
    final promoRank = pos.turn == Side.white ? 7 : 0;
    if (rank == promoRank && spec.promotion == null) {
      reasons.add('Terfi taşı belirtilmemiş.');
    }
  }
  final role = spec.role;
  if (role != null) {
    final hasRole = pos.pieces.any((e) => e.$2.side == pos.turn && e.$2.role == role);
    if (!hasRole) {
      reasons.add('$side tarafının bu türde taşı yok.');
    } else if (spec.to != null) {
      reasons.add('$side tarafının hiçbir ${_roleTr(role)} '
          '${Square.name(spec.to!)} karesine gidemez.');
    }
  }
  final target = spec.to == null ? null : pos.pieceAt(spec.to!);
  if (target != null && target.side == pos.turn) {
    reasons.add('${Square.name(spec.to!)} karesinde kendi taşı var.');
  }

  // Would the move be legal for the other side? Hints at a skipped move.
  final flipped = _withTurn(pos, pos.turn.opposite);
  if (flipped != null && parseMove(flipped, token).isResolved) {
    reasons.add('Hamle ${pos.turn.opposite.trName} için yasal olurdu: karnede '
        'bir hamle eksik ya da fazla yazılmış olabilir (hamle sırası kaymış).');
  }
  if (reasons.isEmpty) reasons.add('Bu konumda böyle bir yasal hamle yok.');
  return reasons;
}

Position? _withTurn(Position pos, Side side) {
  final parts = pos.fen.split(' ');
  parts[1] = side == Side.white ? 'w' : 'b';
  parts[3] = '-';
  try {
    return Position.fromFen(parts.join(' '));
  } on FormatException {
    return null;
  }
}

String _roleTr(Role r) => switch (r) {
      Role.pawn => 'piyonu',
      Role.knight => 'atı',
      Role.bishop => 'fili',
      Role.rook => 'kalesi',
      Role.queen => 'veziri',
      Role.king => 'şahı',
    };
