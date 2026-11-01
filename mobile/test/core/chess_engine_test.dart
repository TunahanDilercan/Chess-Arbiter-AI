import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/chess/fuzzy.dart';
import 'package:mobile/core/chess/notation.dart';
import 'package:mobile/core/chess/pgn.dart';
import 'package:mobile/core/chess/position.dart';
import 'package:mobile/core/chess/san.dart';
import 'package:mobile/core/chess/types.dart';

int perft(Position pos, int depth) {
  if (depth == 1) return pos.legalMoves.length;
  var n = 0;
  for (final m in pos.legalMoves) {
    n += perft(pos.play(m), depth - 1);
  }
  return n;
}

Position playSans(List<String> sans, [String? fen]) {
  var pos = fen == null ? Position.initial() : Position.fromFen(fen);
  for (final s in sans) {
    final r = parseMove(pos, s);
    expect(r.isResolved, isTrue, reason: 'cannot play $s in ${pos.fen}');
    pos = pos.play(r.move!);
  }
  return pos;
}

void main() {
  group('perft (standard reference counts)', () {
    final cases = <(String, List<int>)>[
      (Position.startFen, [20, 400, 8902, 197281]),
      ('r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
          [48, 2039, 97862]),
      ('8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1', [14, 191, 2812, 43238]),
      ('r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1',
          [6, 264, 9467]),
      ('rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8',
          [44, 1486, 62379]),
      ('r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10',
          [46, 2079, 89890]),
    ];
    for (final (fen, counts) in cases) {
      test(fen, () {
        final pos = Position.fromFen(fen);
        for (var d = 1; d <= counts.length; d++) {
          expect(perft(pos, d), counts[d - 1], reason: 'depth $d');
        }
      });
    }
  });

  group('FEN', () {
    test('round trip start position', () {
      expect(Position.initial().fen, Position.startFen);
    });
    test('en passant square only shown when capture is legal', () {
      final pos = playSans(['e4']);
      expect(pos.fen.split(' ')[3], '-');
      final p2 = playSans(['e4', 'a6', 'e5', 'd5']);
      expect(p2.fen.split(' ')[3], 'd6');
    });
    test('rejects malformed FEN', () {
      expect(() => Position.fromFen('8/8/8/8/8/8/8/8 w - - 0 1'),
          throwsFormatException);
      expect(() => Position.fromFen('rnbqkbnr/pppppppp/8/8 w - - 0 1'),
          throwsFormatException);
    });
  });

  group('SAN', () {
    test('disambiguation and suffixes', () {
      final pos = Position.fromFen('1k6/8/8/8/8/8/8/R3K2R w KQ - 0 1');
      final sans = pos.legalMoves.map((m) => toSan(pos, m)).toSet();
      expect(sans, containsAll(['O-O', 'O-O-O', 'Ra8+', 'Rh8+']));
      final mate = Position.fromFen('k7/8/1K6/8/8/8/8/7R w - - 0 1');
      expect(mate.legalMoves.map((m) => toSan(mate, m)), contains('Rh8#'));
    });
    test('file/rank disambiguation', () {
      final pos = Position.fromFen('k7/8/8/8/N7/8/N7/K7 w - - 0 1');
      final sans = pos.legalMoves.map((m) => toSan(pos, m)).toSet();
      expect(sans,
          containsAll(['N4c3', 'N2c3', 'Nb2', 'Nb4', 'Nc1', 'Nc5', 'Nb6+']));
    });
    test('promotion and en passant SAN', () {
      final pos = Position.fromFen('8/4P1k1/8/3pP3/8/8/8/4K3 w - d6 0 1');
      final sans = pos.legalMoves.map((m) => toSan(pos, m)).toSet();
      expect(sans, containsAll(['e8=Q', 'e8=N+', 'exd6']));
    });
    test('tolerant parse: slips are warnings, not illegal', () {
      final pos = playSans(['e4', 'd5']);
      expect(parseMove(pos, 'exd5').status, SanParseStatus.exact);
      expect(parseMove(pos, 'ed5').status, SanParseStatus.notationWarning);
      expect(parseMove(pos, 'e4d5').status, SanParseStatus.exact);
      expect(parseMove(pos, 'Nf3').status, SanParseStatus.exact);
      expect(parseMove(pos, 'Ng1-f3').status, SanParseStatus.exact);
      expect(parseMove(pos, 'Nf3+').status, SanParseStatus.notationWarning);
      expect(parseMove(pos, 'Nf6').status, SanParseStatus.illegal);
      expect(parseMove(pos, 'hello').status, SanParseStatus.unparseable);
      expect(parseMove(pos, '?').status, SanParseStatus.empty);
    });
    test('ambiguous knight move is never guessed', () {
      final pos = playSans(['Nf3', 'a6', 'Nc3', 'a5', 'Ne4', 'a4']);
      final r = parseMove(pos, 'Ng5');
      expect(r.status, SanParseStatus.ambiguous);
      expect(r.candidates.length, 2);
      expect(parseMove(pos, 'Nfg5').isResolved, isTrue);
    });
    test('missing promotion piece is ambiguous', () {
      final pos = Position.fromFen('8/4P1k1/8/8/8/8/8/4K3 w - - 0 1');
      expect(parseMove(pos, 'e8').status, SanParseStatus.ambiguous);
      expect(parseMove(pos, 'e8Q').isResolved, isTrue);
    });
    test('illegal explanations', () {
      // Pinned knight.
      final pinned = Position.fromFen('4k3/8/8/8/4r3/8/4N3/4K3 w - - 0 1');
      expect(explainIllegal(pinned, 'Nc3').join(), contains('şah'));
      // Castling after the king moved.
      final moved = playSans(['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Bc5', 'Ke2', 'Nf6', 'Ke1', 'd6']);
      expect(parseMove(moved, 'O-O').status, SanParseStatus.illegal);
      expect(explainIllegal(moved, 'O-O').join(), contains('rok hakkını'));
      // A black move written on white's turn → skipped move hint.
      expect(explainIllegal(Position.initial(), 'e5').join(), contains('eksik'));
    });
  });

  group('notation normalisation', () {
    test('Turkish letters', () {
      expect(normalizeMove('Af3', NotationLocale.tr), 'Nf3');
      expect(normalizeMove('Kxe8', NotationLocale.tr), 'Rxe8');
      expect(normalizeMove('Şg1', NotationLocale.tr), 'Kg1');
      expect(normalizeMove('Vh4+', NotationLocale.tr), 'Qh4+');
      expect(normalizeMove('Fb5', NotationLocale.tr), 'Bb5');
      expect(normalizeMove('e8V', NotationLocale.tr), 'e8=Q');
    });
    test('castling and glyph variants', () {
      expect(normalizeMove('0-0', NotationLocale.en), 'O-O');
      expect(normalizeMove('000', NotationLocale.en), 'O-O-O');
      expect(normalizeMove('o-o+', NotationLocale.tr), 'O-O+');
      expect(normalizeMove('Nfl', NotationLocale.en), 'Nf1');
      expect(normalizeMove('e×d5', NotationLocale.en), 'exd5');
      expect(normalizeMove('♘f3', NotationLocale.en), 'Nf3');
      expect(normalizeMove('12. Nf3', NotationLocale.en), 'Nf3');
      expect(normalizeMove('nf3', NotationLocale.en), 'Nf3');
      expect(normalizeMove('e8(Q)', NotationLocale.en), 'e8=Q');
    });
    test('French R is king, T is rook — promotion not double-mapped', () {
      expect(normalizeMove('Rf1', NotationLocale.fr), 'Kf1');
      expect(normalizeMove('e8T', NotationLocale.fr), 'e8=R');
    });
    test('localized display', () {
      expect(localizeSan('Nxf3+', NotationLocale.tr), 'Axf3+');
      expect(localizeSan('O-O', NotationLocale.tr), 'O-O');
      expect(localizeSan('Rxe8', NotationLocale.tr), 'Kxe8');
    });
  });

  group('PGN', () {
    test('headers, comments, variations, NAGs, results', () {
      const text = '''
[Event "Test Open"]
[White "A"]
[Black "B"]
[Result "1-0"]

1.e4 {King pawn} e5 2. Nf3 (2. f4 exf4) Nc6 \$1 3...a6? ; comment
4. 0-0 1-0
''';
      final g = parsePgn(text).single;
      expect(g.headers['Event'], 'Test Open');
      expect(g.moves, ['e4', 'e5', 'Nf3', 'Nc6', 'a6?', '0-0']);
      expect(g.result, '1-0');
    });
    test('bare move list and multiple games', () {
      expect(parsePgn('e4, e5\nNf3 Nc6').single.moves, ['e4', 'e5', 'Nf3', 'Nc6']);
      expect(parsePgn('1 e4 e5 2 00 ?').single.moves, ['e4', 'e5', '00', '?']);
      final two = parsePgn('[Event "1"]\n1.e4 *\n\n[Event "2"]\n1.d4 *');
      expect(two.length, 2);
      expect(two[1].moves, ['d4']);
    });
    test('writer round trip', () {
      final out = writePgn(
          headers: {'White': 'A', 'Black': 'B'},
          sans: ['e4', 'e5', 'Nf3'],
          comments: {1: 'not'});
      expect(out, contains('[Result "*"]'));
      expect(out, contains('1. e4 e5 {not} 2. Nf3 *'));
      expect(parsePgn(out).single.moves, ['e4', 'e5', 'Nf3']);
    });
  });

  group('fuzzy ranking', () {
    test('indel ratio matches python-Levenshtein', () {
      expect(indelRatio('Nf3', 'Nf3'), 1);
      expect(indelRatio('8f3', 'Bf3'), closeTo(2 / 3, 1e-9));
    });
    test('confused reading ranks the intended move first', () {
      final pos = playSans(['e4', 'e5', 'Nf3', 'Nc6']);
      expect(rankMoves(pos, '8b5').first.san, 'Bb5');
      expect(rankMoves(pos, 'Mc3').first.san, 'Nc3');
    });
  });

  test('castling rights lost when rook captured', () {
    final pos = Position.fromFen('r3k2r/8/8/8/8/8/6B1/R3K2R w KQkq - 0 1');
    final after = pos.play(pos.legalMoves.firstWhere((m) =>
        m.from == Square.parse('g2') && m.to == Square.parse('a8')));
    expect(after.castlingFen, 'KQk');
  });
}
