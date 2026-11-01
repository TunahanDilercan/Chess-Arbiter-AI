import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/chess/notation.dart';
import 'package:mobile/core/chess/position.dart';
import 'package:mobile/core/chess/san.dart';
import 'package:mobile/core/chess/types.dart';

import 'oracle_data.dart';

int perft(Position pos, int depth) {
  if (depth == 0) return 1;
  if (depth == 1) return pos.legalMoves.length;
  var n = 0;
  for (final m in pos.legalMoves) {
    n += perft(pos.play(m), depth - 1);
  }
  return n;
}

/// Move generation vs Stockfish 17.1 ("go perft"), SAN vs python-chess, and
/// SAN / notation round trips for every legal move of every sampled position.
void main() {
  if (!hasPerft) {
    test('perft', () {}, skip: 'run tool/gen_oracle_suite.py first');
    return;
  }
  final data = loadPerft();
  final positions = (data['positions'] as List).cast<Map<String, dynamic>>();
  final deep = (data['deep'] as List).cast<Map<String, dynamic>>();

  test('${positions.length} positions: perft-divide(3) equals Stockfish', () {
    var nodes = 0;
    for (final r in positions) {
      final fen = r['fen'] as String;
      final pos = Position.fromFen(fen);
      final divide = (r['divide3'] as Map).cast<String, int>();
      expect(pos.legalMoves.map((m) => m.uci).toSet(), divide.keys.toSet(), reason: fen);
      for (final m in pos.legalMoves) {
        expect(perft(pos.play(m), 2), divide[m.uci], reason: '$fen ${m.uci}');
      }
      nodes += r['nodes3'] as int;
    }
    // ignore: avoid_print
    print('perft(3) nodes verified: $nodes');
  }, timeout: const Timeout(Duration(minutes: 30)));

  for (final r in deep) {
    test('deep perft-divide(${r['depth']}) ${r['fen']}', () {
      final pos = Position.fromFen(r['fen'] as String);
      final divide = (r['divide'] as Map).cast<String, int>();
      final depth = r['depth'] as int;
      expect(pos.legalMoves.map((m) => m.uci).toSet(), divide.keys.toSet());
      for (final m in pos.legalMoves) {
        expect(perft(pos.play(m), depth - 1), divide[m.uci], reason: m.uci);
      }
    }, timeout: const Timeout(Duration(minutes: 30)));
  }

  test('legal SAN lists equal python-chess', () {
    for (final r in positions) {
      final pos = Position.fromFen(r['fen'] as String);
      final ours = [for (final m in pos.legalMoves) toSan(pos, m)]..sort();
      final theirs = (r['sans'] as List).cast<String>()..sort();
      expect(ours, theirs, reason: r['fen'] as String);
    }
  });

  test('every legal move round-trips through SAN, 5 notations, UCI and slips', () {
    var checked = 0;
    for (final r in positions) {
      final pos = Position.fromFen(r['fen'] as String);
      for (final m in pos.legalMoves) {
        final san = toSan(pos, m);
        final where = '${r['fen']} $san';
        expect(parseMove(pos, san).move, m, reason: where);
        expect(parseMove(pos, san).status, SanParseStatus.exact, reason: where);
        for (final loc in NotationLocale.values) {
          final written = localizeSan(san, loc);
          expect(parseMove(pos, normalizeMove(written, loc)).move, m,
              reason: '$where ${loc.code} "$written"');
        }
        expect(parseMove(pos, m.uci).move, m, reason: '$where uci');
        // Missing check sign is a notation slip, never a different move.
        final bare = san.replaceAll(RegExp(r'[+#]'), '');
        final slip = parseMove(pos, bare);
        expect(slip.move, m, reason: '$where bare');
        if (bare != san) expect(slip.status, SanParseStatus.notationWarning, reason: where);
        // Long algebraic with a dash: "Ng1-f3", "e2-e4".
        if (!pos.isCastle(m)) {
          final piece = pos.pieceAt(m.from)!;
          final long = '${piece.role.sanLetter}${Square.name(m.from)}-${Square.name(m.to)}'
              '${m.promotion == null ? '' : '=${m.promotion!.sanLetter}'}';
          expect(parseMove(pos, long).move, m, reason: '$where long "$long"');
        }
        checked++;
      }
    }
    // ignore: avoid_print
    print('round-tripped moves: $checked');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
