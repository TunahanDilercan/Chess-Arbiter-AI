import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/arbiter/analysis.dart';
import 'package:mobile/core/arbiter/compare.dart';
import 'package:mobile/core/arbiter/game_record.dart';
import 'package:mobile/core/arbiter/material.dart';
import 'package:mobile/core/arbiter/report.dart';
import 'package:mobile/core/arbiter/time_control.dart';
import 'package:mobile/core/arbiter/tools.dart';
import 'package:mobile/core/chess/notation.dart';
import 'package:mobile/core/chess/position.dart';
import 'package:mobile/core/chess/types.dart';

List<String> moves(String s) => s.split(' ');

void main() {
  group('replay timeline', () {
    test('threefold is claimable, not automatic', () {
      final a = analyzeGame(moves('Nf3 Nf6 Ng1 Ng8 Nf3 Nf6 Ng1 Ng8 e4'));
      final tf = a.events.where((e) => e.kind == RuleKind.threefold).toList();
      expect(tf.map((e) => e.ply), [7]); // start position, 3rd occurrence
      expect(tf.every((e) => e.nature == RuleNature.claimable), isTrue);
      expect(a.end, isNull);
      expect(a.plies.last.state, PlyState.ok); // game continues
    });

    test('fivefold ends the game automatically; later moves flagged', () {
      final cycle = 'Nf3 Nf6 Ng1 Ng8';
      final a = analyzeGame(moves('$cycle $cycle $cycle $cycle e4 e5'));
      expect(a.end?.kind, RuleKind.fivefold);
      expect(a.end?.ply, 15);
      expect(a.end?.result, '1/2-1/2');
      expect(a.plies[16].state, PlyState.afterGameEnd);
      expect(a.events.any((e) => e.kind == RuleKind.movesAfterEnd), isTrue);
    });

    test('lost castling rights make positions different (9.2.2)', () {
      final a = analyzeGame(moves('e4 e5 Ke2 Ke7 Ke1 Ke8 Ke2 Ke7 Ke1 Ke8'));
      final g = a.repetitions.firstWhere((g) => g.occurrences.contains(6));
      expect(g.occurrences, [6, 10]);
      expect(g.nearMisses.single.positionIndex, 2);
      expect(g.nearMisses.single.reason, contains('rok'));
      expect(a.events.where((e) => e.kind == RuleKind.threefold), isEmpty);
      final v = checkClaim(a,
          positionIndex: 10, type: ClaimType.threefold,
          timeControl: TimeControl.standard);
      expect(v.valid, isFalse);
      expect(v.nearMisses, isNotEmpty);
      expect(v.consequences.first, contains('2 dakika'));
    });

    test('en passant possibility makes positions different (9.2.2)', () {
      final a = analyzeGame(
          moves('e4 Nf6 e5 d5 Nf3 Ng8 Ng1 Nf6 Nf3 Ng8 Ng1 Nf6'));
      expect(a.positions[4].legalEpSquare, isNotNull);
      final v = checkClaim(a,
          positionIndex: 12, type: ClaimType.threefold,
          timeControl: TimeControl.standard);
      expect(v.valid, isFalse);
      expect(v.matchingPositions, [8, 12]);
      expect(v.nearMisses.single.reason, contains('geçerken'));
    });

    test('fifty-move claim and 75-move automatic draw', () {
      const fen = '8/8/8/4k3/8/8/8/R3K3 w - - 98 80';
      final a = analyzeGame(moves('Ra2 Kd5'), startFen: fen);
      expect(a.events.single.kind, RuleKind.fiftyMoves);
      expect(a.events.single.nature, RuleNature.claimable);
      bool claim(int idx, [String? intended]) => checkClaim(a,
              positionIndex: idx, type: ClaimType.fiftyMoves,
              timeControl: TimeControl.standard, intendedMove: intended)
          .valid;
      expect(claim(2), isTrue); // 9.3.2
      expect(claim(1), isFalse);
      expect(claim(1, 'Kd5'), isTrue); // 9.3.1
      expect(claim(1, 'Kd4'), isTrue);

      final b = analyzeGame(moves('Ra2 Kd5'), startFen: '8/8/8/4k3/8/8/8/R3K3 w - - 148 80');
      expect(b.end?.kind, RuleKind.seventyFiveMoves);
      expect(b.end?.ply, 1);
    });

    test('checkmate takes precedence over the 75-move rule', () {
      final a = analyzeGame(['Rh8#'], startFen: 'k7/8/1K6/8/8/8/8/7R w - - 149 100');
      expect(a.end?.kind, RuleKind.checkmate);
      expect(a.end?.result, '1-0');
    });

    test('checkmate, stalemate, dead position', () {
      expect(analyzeGame(moves('f3 e5 g4 Qh4#')).end?.result, '0-1');
      expect(analyzeGame(['Qb6'], startFen: 'k7/8/2K5/8/8/8/8/1Q6 w - - 0 1').end?.kind,
          RuleKind.stalemate);
      final dead = analyzeGame(['Kxd2'], startFen: '4k3/8/8/8/8/8/3r4/2B1K3 w - - 0 1');
      expect(dead.end?.kind, RuleKind.deadPosition);
    });

    test('illegal move stops replay, keeps raw tokens and explains', () {
      final a = analyzeGame(moves('e4 e5 Ke3 Nc6 Nf3'));
      expect(a.stopPly, 2);
      expect(a.plies[2].state, PlyState.illegal);
      expect(a.plies[2].reasons, isNotEmpty);
      expect(a.plies[2].suggestions.first.san, 'Ke2');
      expect(a.plies[3].state, PlyState.notReached);
      expect(a.plies[4].raw, 'Nf3');
    });

    test('missing move shows up as a turn-shift hint', () {
      final a = analyzeGame(moves('e4 Nf3 Nc6'));
      expect(a.plies[1].state, PlyState.illegal);
      expect(a.plies[1].reasons.join(), contains('eksik'));
    });

    test('Turkish scoresheet', () {
      final a = analyzeGame(moves('e4 e5 Af3 Ac6 Fb5 a6 Fa4 Af6 O-O Fe7 Ke1'),
          locale: NotationLocale.tr);
      expect(a.stopPly, isNull);
      expect(a.sans.last, 'Re1');
    });

    test('ambiguous written move is not guessed', () {
      final a = analyzeGame(moves('Nf3 a6 Nc3 a5 Ne4 a4 Ng5'));
      expect(a.plies[6].state, PlyState.ambiguous);
      expect(a.plies[6].ambiguousCandidates.toSet(), {'Nfg5', 'Neg5'});
    });
  });

  group('claims', () {
    final a = analyzeGame(moves('Nf3 Nf6 Ng1 Ng8 Nf3 Nf6 Ng1'));
    test('9.2.1.1 intended move', () {
      final v = checkClaim(a,
          positionIndex: 7, type: ClaimType.threefold,
          timeControl: TimeControl.standard, intendedMove: 'Ng8');
      expect(v.valid, isTrue);
      expect(v.claimant, Side.black);
      expect(v.intendedSan, 'Ng8');
      expect(v.consequences.first, contains('berabere'));
    });
    test('incorrect claim penalty depends on time control', () {
      final v = checkClaim(a,
          positionIndex: 7, type: ClaimType.threefold,
          timeControl: TimeControl.blitz);
      expect(v.valid, isFalse);
      expect(v.consequences.first, contains('1 dakika'));
    });
    test('illegal intended move makes the claim incorrect', () {
      final v = checkClaim(a,
          positionIndex: 7, type: ClaimType.threefold,
          timeControl: TimeControl.standard, intendedMove: 'Ng5');
      expect(v.valid, isFalse);
      expect(v.details.first, contains('yasal değil'));
    });
  });

  group('mating material', () {
    MateAbility mate(String fen, Side s) => canCheckmate(Position.fromFen(fen), s);
    test('known cases', () {
      expect(mate('4k3/8/8/8/8/8/8/2N1K3 w - - 0 1', Side.white), MateAbility.impossible);
      expect(mate('4k3/7p/8/8/8/8/8/2N1K3 w - - 0 1', Side.white), MateAbility.possible);
      expect(mate('4k3/8/8/8/8/8/8/2B1K3 w - - 0 1', Side.white), MateAbility.impossible);
      expect(mate('2b1k3/8/8/8/8/8/8/2B1K3 w - - 0 1', Side.white),
          MateAbility.possible); // opposite-coloured bishops
      expect(mate('3bk3/8/8/8/8/8/8/2B1K3 w - - 0 1', Side.white),
          MateAbility.impossible); // same-coloured bishops: dead
      expect(isDeadByMaterial(Position.fromFen('3bk3/8/8/8/8/8/8/2B1K3 w - - 0 1')),
          isTrue);
      expect(mate('4k3/8/8/8/8/8/8/1NN1K3 w - - 0 1', Side.white), MateAbility.possible);
      expect(mate('4k3/8/8/8/8/8/7P/4K3 w - - 0 1', Side.black), MateAbility.impossible);
      expect(mate('3qk3/8/8/8/8/8/8/2N1K3 w - - 0 1', Side.white), MateAbility.unclear);
    });
  });

  group('illegal move advisor (7.5.5)', () {
    test('first offence gives the opponent extra time', () {
      final adv = adviseIllegalMove(
          before: Position.initial(), offender: Side.white,
          timeControl: TimeControl.standard, previousOffences: 0,
          writtenMove: 'Nf4');
      expect(adv.isLoss, isFalse);
      expect(adv.headline, contains('+2 dk'));
      expect(adv.samePieceMoves, containsAll(['Nf3', 'Nh3', 'Na3', 'Nc3']));
      final rapid = adviseIllegalMove(
          before: Position.initial(), offender: Side.white,
          timeControl: TimeControl.rapid, previousOffences: 0);
      expect(rapid.headline, contains('+1 dk'));
    });
    test('second offence loses unless opponent cannot mate', () {
      final lose = adviseIllegalMove(
          before: Position.fromFen('k7/8/8/8/8/8/7Q/K7 b - - 0 1'),
          offender: Side.black, timeControl: TimeControl.standard,
          previousOffences: 1);
      expect(lose.isLoss, isTrue);
      final draw = adviseIllegalMove(
          before: Position.fromFen('k7/8/8/8/8/8/7Q/K7 w - - 0 1'),
          offender: Side.white, timeControl: TimeControl.standard,
          previousOffences: 1);
      expect(draw.isDraw, isTrue);
    });
    test('rapid without supervision after opponent moved: stands', () {
      final adv = adviseIllegalMove(
          before: Position.initial(), offender: Side.white,
          timeControl: TimeControl.rapid, previousOffences: 0,
          adequateSupervision: false, opponentHasMovedSince: true);
      expect(adv.headline, contains('geçerli kalır'));
    });
  });

  group('flag fall (6.9)', () {
    test('lone king opponent → draw; helpmate material → loss', () {
      final draw = checkFlagFall(
          Position.fromFen('4k3/8/8/8/8/8/4P3/4K3 w - - 0 1'), Side.white);
      expect(draw.result, '1/2-1/2');
      final loss = checkFlagFall(
          Position.fromFen('4k3/8/8/8/8/8/4P3/2n1K3 w - - 0 1'), Side.white);
      expect(loss.result, '0-1');
    });
  });

  group('scoresheet comparison', () {
    test('detects a move missing from one sheet', () {
      final c = compareSheets(moves('e4 e5 Nf3 Nc6 Bb5 a6'), moves('e4 e5 Nf3 Bb5 a6'));
      expect(c.agreedPlies, 3);
      final only = c.rows.where((r) => r.kind == RowKind.onlyA).single;
      expect(only.aIndex, 3);
      expect(c.summary.join('\n'), contains('B karnesinde eksik'));
    });
    test('different notation of the same move is not a difference', () {
      final c = compareSheets(moves('e4 e5 Nf3'), moves('e2-e4 e7e5 Ng1f3'));
      expect(c.identical, isTrue);
      final tr = compareSheets(moves('e4 e5 Nf3'), moves('e4 e5 Af3'),
          localeB: NotationLocale.tr);
      expect(tr.identical, isTrue);
    });
  });

  test('record JSON round trip and report', () {
    final rec = GameRecord(
      id: 'abc', createdAt: DateTime(2026, 10, 31), updatedAt: DateTime(2026, 10, 31),
      headers: const {'White': 'Ali', 'Black': 'Ayşe', 'Event': 'Kış Açık'},
      tokens: moves('e4 e5 Ke3'), locale: NotationLocale.tr,
      timeControl: TimeControl.rapid, source: GameSource.board,
    ).withLog(ArbiterLogEntry(
        at: DateTime(2026, 10, 31, 14), kind: LogKind.illegalMove,
        title: 'Beyaz kural dışı hamle', ply: 2, side: Side.white));
    final back = GameRecord.fromJson(rec.toJson());
    expect(back.tokens, rec.tokens);
    expect(back.locale, NotationLocale.tr);
    expect(back.timeControl, TimeControl.rapid);
    expect(back.illegalMoveCount(Side.white), 1);
    final text = reportAsText(buildReport(back, analyzeGame(back.tokens, locale: back.locale)));
    expect(text, contains('Kış Açık'));
    expect(text, contains('kural dışı hamle'));
    expect(text, contains('Ke3'));
  });

  group('FIDE edge cases', () {
    test('en passant blocked by a pin does not make positions different', () {
      final pos = Position.fromFen('4k3/2p5/8/KP5r/8/8/8/8 b - - 0 1');
      final after = pos.play(pos.legalMoves.firstWhere((m) =>
          m.from == Square.parse('c7') && m.to == Square.parse('c5')));
      expect(after.epSquare, Square.parse('c6'));
      expect(after.legalEpSquare, isNull);
      expect(after.fen.split(' ')[3], '-');
      expect(after.repetitionKey.endsWith(' -'), isTrue);
    });

    test('intended capture resets the 50-move count (claim incorrect)', () {
      final a = analyzeGame(const [], startFen: '8/8/8/4k3/8/8/4p3/R3K3 w - - 99 80');
      bool claim(String move) => checkClaim(a,
              positionIndex: 0, type: ClaimType.fiftyMoves,
              timeControl: TimeControl.standard, intendedMove: move)
          .valid;
      expect(claim('Ra2'), isTrue);
      expect(claim('Kxe2'), isFalse);
    });

    test('rook move loses only that side\'s castling right', () {
      final a = analyzeGame(moves('Nf3 Nf6 Rg1 Ng8 Rh1 Nf6'));
      expect(a.finalPosition.castlingFen, 'Qkq');
      expect(a.repetitions.where((g) => g.occurrences.length > 1), isEmpty);
    });

    test('claim on the claimant\'s own move that creates the third occurrence', () {
      final a = analyzeGame(moves('Nf3 Nf6 Ng1 Ng8 Nf3 Nf6 Ng1 Ng8 Nf3 Nf6'));
      // White to move at position 10; Ng1 would create the 3rd occurrence of
      // the position after 2.Ng1 (indices 3, 7 → +1).
      final v = checkClaim(a,
          positionIndex: 10, type: ClaimType.threefold,
          timeControl: TimeControl.standard, intendedMove: 'Ng1');
      expect(v.valid, isTrue);
      expect(v.matchingPositions, [3, 7]);
    });

    test('flag fall with K+N vs K+pawns: knight side can still win', () {
      final v = checkFlagFall(
          Position.fromFen('7k/6pp/8/8/8/8/8/4K1N1 b - - 0 1'), Side.black);
      expect(v.result, '1-0');
    });
  });

  group('review fixes', () {
    test('blocked kings-and-pawns positions are not judged by material', () {
      final pos = Position.fromFen('k7/8/8/p1p1p1p1/P1P1P1P1/8/8/K7 w - - 0 1');
      expect(canCheckmate(pos, Side.white), MateAbility.unclear);
      expect(checkFlagFall(pos, Side.black).result, '?');
      final adv = adviseIllegalMove(
          before: pos, offender: Side.black,
          timeControl: TimeControl.standard, previousOffences: 1);
      expect(adv.needsJudgement, isTrue);
      // Mobile pawns are still "possible".
      expect(canCheckmate(Position.fromFen('k7/8/8/8/8/8/P7/K7 w - - 0 1'), Side.white),
          MateAbility.possible);
    });

    test('flag fall after mate or stalemate on the board', () {
      final mated = Position.fromFen('k6R/8/1K6/8/8/8/8/8 b - - 0 1');
      expect(checkFlagFall(mated, Side.white).result, '1-0');
      final stale = Position.fromFen('k7/8/1QK5/8/8/8/8/8 b - - 0 1');
      expect(checkFlagFall(stale, Side.white).result, '1/2-1/2');
    });

    test('illegal intended move: no "must be played", and claim is a draw offer', () {
      final a = analyzeGame(moves('Nf3 Nf6 Ng1 Ng8 Nf3 Nf6 Ng1'));
      final v = checkClaim(a,
          positionIndex: 7, type: ClaimType.threefold,
          timeControl: TimeControl.standard, intendedMove: 'Qh4');
      expect(v.valid, isFalse);
      final text = v.consequences.join(' ');
      expect(text, isNot(contains('oynanmalıdır')));
      expect(text, contains('başka bir yasal hamle'));
      expect(text, contains('9.1.2.3'));
    });

    test('fifty-move claim is reported when the start already exceeds 100', () {
      final a = analyzeGame(['Ra2'], startFen: '8/8/8/4k3/8/8/8/R3K3 w - - 120 90');
      expect(a.events.single.kind, RuleKind.fiftyMoves);
    });

    test('draw-offer marks are ignored when reading moves', () {
      expect(normalizeMove('Af3 (=)', NotationLocale.tr), 'Nf3');
      expect(normalizeMove('Nf3=', NotationLocale.en), 'Nf3');
      expect(normalizeMove('e8=Q', NotationLocale.en), 'e8=Q');
      expect(analyzeGame(['e4', 'e5', 'Nf3=']).stopPly, isNull);
    });

    test('stalemate on the 150th half-move takes precedence (draw either way)', () {
      final a = analyzeGame(['Qb6'], startFen: 'k7/8/2K5/8/8/8/8/1Q6 w - - 149 120');
      expect(a.end?.kind, RuleKind.stalemate);
    });

    test('castling right blocked by pieces still counts (positions equal)', () {
      final a = analyzeGame(moves('Nf3 Nf6 Ng1 Ng8 Nf3 Nf6 Ng1 Ng8'));
      // Start position: castling impossible (pieces between) but rights intact.
      expect(a.occurrencesUpTo(8), [0, 4, 8]);
    });
  });
}
