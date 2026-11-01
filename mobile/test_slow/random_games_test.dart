import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/arbiter/analysis.dart';
import 'package:mobile/core/arbiter/material.dart';

/// Thousands of games steered towards repetitions, 50/75-move endings and
/// dead positions (tool/gen_oracle_fixture.py 4000 test_slow/data/random_games.json 99).
void main() {
  final file = File('test_slow/data/random_games.json');
  if (!file.existsSync()) {
    test('random games', () {}, skip: 'generate test_slow/data/random_games.json first');
    return;
  }
  final games = (jsonDecode(file.readAsStringSync()) as List).cast<Map<String, dynamic>>();
  const chunk = 250;
  for (var start = 0; start < games.length; start += chunk) {
    final end = (start + chunk).clamp(0, games.length);
    test('games $start..${end - 1} agree with python-chess', () {
      for (var g = start; g < end; g++) {
        final game = games[g];
        final sans = (game['sans'] as String).split(' ');
        final flags = (game['flags'] as String).split(',');
        final clocks = (game['clocks'] as List).cast<int>();
        final fens = (game['fens'] as Map).cast<String, String>();
        final a = analyzeGame(sans, startFen: game['start'] as String);
        expect(a.stopPly, isNull, reason: 'game $g');
        final counts = <String, int>{a.positions.first.repetitionKey: 1};
        for (var i = 0; i < sans.length; i++) {
          final p = a.plies[i];
          final where = 'game $g ply $i (${sans[i]})';
          expect(p.san, sans[i], reason: where);
          final pos = p.after!;
          final f = flags[i];
          final n = counts.update(pos.repetitionKey, (v) => v + 1, ifAbsent: () => 1);
          expect(pos.isCheck, f.contains('c'), reason: '$where check');
          expect(pos.isCheckmate, f.contains('M'), reason: '$where mate');
          expect(pos.isStalemate, f.contains('S'), reason: '$where stalemate');
          expect(isDeadByMaterial(pos), f.contains('D'), reason: '$where dead');
          expect(n >= 3, f.contains('3'), reason: '$where 3x');
          expect(n >= 5, f.contains('5'), reason: '$where 5x');
          expect(pos.halfmoves, clocks[i], reason: '$where clock');
          final fen = fens['$i'];
          if (fen != null) expect(pos.fen, fen, reason: '$where fen');
        }
        final last = flags.last;
        expect(a.end != null, RegExp('[MSD57]').hasMatch(last), reason: 'game $g end ($last)');
        final finalKinds = a.eventsAt(sans.length - 1).map((e) => e.kind).toSet();
        if (last.contains('7') && !RegExp('[MSD]').hasMatch(last)) {
          expect(finalKinds, contains(RuleKind.seventyFiveMoves), reason: 'game $g 75');
        }
        if (last.contains('5') && !RegExp('[MSD]').hasMatch(last)) {
          expect(finalKinds, contains(RuleKind.fivefold), reason: 'game $g fivefold');
        }
      }
    }, timeout: const Timeout(Duration(minutes: 10)));
  }
}
