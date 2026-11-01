/// "Can this side checkmate by any series of legal moves?" — the question
/// behind 5.2.2 (dead position), 6.9 (flag fall) and 7.5.5 (second illegal
/// move). Material-based and deliberately conservative: it only answers
/// [MateAbility.impossible] for cases that are proven by material alone and
/// returns [MateAbility.unclear] where a helpmate may or may not exist.
/// Blocked-pawn fortresses are not detected.
library;

import '../chess/position.dart';
import '../chess/types.dart';

enum MateAbility { possible, impossible, unclear }

class _Material {
  int pawns = 0, knights = 0, rooks = 0, queens = 0;
  int lightBishops = 0, darkBishops = 0;

  int get bishops => lightBishops + darkBishops;
  bool get loneKing =>
      pawns + knights + rooks + queens + bishops == 0;
  bool get hasMajorOrPawn => pawns + rooks + queens > 0;
}

_Material _count(Position pos, Side side) {
  final m = _Material();
  for (final (sq, p) in pos.pieces) {
    if (p.side != side) continue;
    switch (p.role) {
      case Role.pawn:
        m.pawns++;
      case Role.knight:
        m.knights++;
      case Role.bishop:
        Square.isLight(sq) ? m.lightBishops++ : m.darkBishops++;
      case Role.rook:
        m.rooks++;
      case Role.queen:
        m.queens++;
      case Role.king:
        break;
    }
  }
  return m;
}

MateAbility canCheckmate(Position pos, Side attacker) {
  final a = _count(pos, attacker);
  final d = _count(pos, attacker.opposite);
  if (a.loneKing) return MateAbility.impossible;
  if (a.hasMajorOrPawn) return MateAbility.possible;

  // Attacker has minor pieces only.
  final bothBishopColors = a.lightBishops > 0 && a.darkBishops > 0;
  if (a.knights >= 2 || (a.knights >= 1 && a.bishops >= 1) || bothBishopColors) {
    return MateAbility.possible;
  }

  if (a.knights == 1) {
    // K+N cannot mate a lone king; with any defender material a helpmate
    // (defender's own unit blocking a flight square) is possible.
    if (d.loneKing) return MateAbility.impossible;
    if (d.pawns > 0 || d.knights > 0 || d.bishops > 0 || d.rooks > 0) {
      return MateAbility.possible;
    }
    return MateAbility.unclear; // only queen(s) besides the king
  }

  // Bishops of a single square colour.
  final attackerLight = a.lightBishops > 0;
  if (d.loneKing) return MateAbility.impossible;
  final dSameColorBishopsOnly = d.pawns == 0 &&
      d.knights == 0 &&
      d.rooks == 0 &&
      d.queens == 0 &&
      (attackerLight ? d.darkBishops == 0 : d.lightBishops == 0);
  if (dSameColorBishopsOnly) return MateAbility.impossible;
  if (d.pawns > 0 ||
      d.knights > 0 ||
      (attackerLight ? d.darkBishops > 0 : d.lightBishops > 0)) {
    return MateAbility.possible;
  }
  return MateAbility.unclear; // defender has only rooks/queens
}

/// Dead position by material (subset of 5.2.2).
bool isDeadByMaterial(Position pos) =>
    canCheckmate(pos, Side.white) == MateAbility.impossible &&
    canCheckmate(pos, Side.black) == MateAbility.impossible;

String mateAbilityTr(MateAbility m, Side side) => switch (m) {
      MateAbility.possible =>
        '${side.trName} teorik olarak mat edebilir (yardımlı mat dahil).',
      MateAbility.impossible =>
        '${side.trName} hiçbir yasal hamle dizisiyle mat edemez.',
      MateAbility.unclear =>
        '${side.trName} için mat imkânı malzemeden kesin çıkarılamıyor; '
            'hakem konumu değerlendirmeli.',
    };
