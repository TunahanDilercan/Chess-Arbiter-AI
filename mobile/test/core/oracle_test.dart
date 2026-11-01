import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/arbiter/analysis.dart';
import 'package:mobile/core/arbiter/material.dart';

/// Differential test against python-chess (see tool/gen_oracle_fixture.py):
/// SAN, FEN, check/mate/stalemate, dead position, repetition counts, move
/// clocks and automatic game ends must agree on every ply.
void main() {
  final games = (jsonDecode(File('test/fixtures/oracle_games.json').readAsStringSync())
          as List)
      .cast<Map<String, dynamic>>();

  test('fixture is non-trivial', () {
    final flags = games.map((g) => g['flags'] as String).join(',');
    expect('3'.allMatches(flags).length, greaterThan(500));
    expect('5'.allMatches(flags).length, greaterThan(10));
    expect('7'.allMatches(flags).length, greaterThan(10));
  });

  for (var g = 0; g < games.length; g++) {
    test('game $g agrees with python-chess', () {
      final game = games[g];
      final sans = (game['sans'] as String).split(' ');
      final flags = (game['flags'] as String).split(',');
      final clocks = (game['clocks'] as List).cast<int>();
      final fens = (game['fens'] as Map).cast<String, String>();
      final a = analyzeGame(sans, startFen: game['start'] as String);

      expect(a.stopPly, isNull, reason: 'replay stopped at ${a.stopPly}');
      for (var i = 0; i < sans.length; i++) {
        final p = a.plies[i];
        final where = 'game $g ply $i (${sans[i]})';
        expect(p.state, PlyState.ok, reason: where);
        expect(p.san, sans[i], reason: where);
        final pos = p.after!;
        final f = flags[i];
        expect(pos.isCheck, f.contains('c'), reason: '$where check');
        expect(pos.isCheckmate, f.contains('M'), reason: '$where mate');
        expect(pos.isStalemate, f.contains('S'), reason: '$where stalemate');
        expect(isDeadByMaterial(pos), f.contains('D'), reason: '$where dead');
        final occ = a.occurrencesUpTo(i + 1).length;
        expect(occ >= 3, f.contains('3'), reason: '$where threefold ($occ)');
        expect(occ >= 5, f.contains('5'), reason: '$where fivefold ($occ)');
        expect(pos.halfmoves, clocks[i], reason: '$where clock');
        final fen = fens['$i'];
        if (fen != null) expect(pos.fen, fen, reason: '$where fen');
      }
      final last = flags.last;
      final endsByRule = RegExp('[MSD57]').hasMatch(last);
      expect(a.end != null, endsByRule, reason: 'game $g end ($last)');
    });
  }
}
