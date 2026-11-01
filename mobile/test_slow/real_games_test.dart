import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/arbiter/analysis.dart';
import 'package:mobile/core/arbiter/material.dart';
import 'package:mobile/core/arbiter/time_control.dart';
import 'package:mobile/core/arbiter/tools.dart';
import 'package:mobile/core/chess/pgn.dart';
import 'package:mobile/core/chess/position.dart';
import 'package:mobile/core/chess/san.dart';

import 'oracle_data.dart';

/// Every ply of thousands of real tournament games, labelled by python-chess.
void main() {
  if (!hasRealGames) {
    test('real games', () {}, skip: 'run tool/gen_oracle_suite.py first');
    return;
  }
  final games = loadRealGames();
  final byFile = <String, List<Map<String, dynamic>>>{};
  for (final g in games) {
    (byFile[g['file'] as String] ??= []).add(g);
  }

  bool claimThreefold(GameAnalysis a, int idx) {
    final pos = a.positions[idx];
    bool valid(String? intended) => checkClaim(a,
            positionIndex: idx,
            type: ClaimType.threefold,
            timeControl: TimeControl.standard,
            intendedMove: intended)
        .valid;
    return valid(null) || pos.legalMoves.any((m) => valid(toSan(pos, m)));
  }

  bool claimFifty(GameAnalysis a, int idx) {
    final pos = a.positions[idx];
    bool valid(String? intended) => checkClaim(a,
            positionIndex: idx,
            type: ClaimType.fiftyMoves,
            timeControl: TimeControl.standard,
            intendedMove: intended)
        .valid;
    return valid(null) || pos.legalMoves.any((m) => valid(toSan(pos, m)));
  }

  for (final entry in byFile.entries) {
    test('${entry.key}: ${entry.value.length} games agree with python-chess', () {
      var plies = 0, claims = 0;
      for (final g in entry.value) {
        final sans = (g['sans'] as String).split(' ');
        final flags = (g['flags'] as String).split(',');
        final clocks = (g['clocks'] as List).cast<int>();
        final fens = (g['fens'] as Map).cast<String, String>();
        final id = '${entry.key}#${g['index']}';
        final a = analyzeGame(sans);
        expect(a.stopPly, isNull, reason: '$id stopped at ${a.stopPly}');
        final counts = <String, int>{a.positions.first.repetitionKey: 1};
        var maxCount = 1;
        for (var i = 0; i < sans.length; i++) {
          final p = a.plies[i];
          final where = '$id ply $i ${sans[i]}';
          expect(p.state, PlyState.ok, reason: where);
          expect(p.san, sans[i], reason: where);
          final pos = p.after!;
          final f = flags[i];
          final n = counts.update(pos.repetitionKey, (v) => v + 1, ifAbsent: () => 1);
          if (n > maxCount) maxCount = n;
          expect(pos.isCheck, f.contains('c'), reason: '$where check');
          expect(pos.isCheckmate, f.contains('M'), reason: '$where mate');
          expect(pos.isStalemate, f.contains('S'), reason: '$where stalemate');
          expect(isDeadByMaterial(pos), f.contains('D'), reason: '$where dead');
          expect(n >= 2, f.contains('2'), reason: '$where 2x');
          expect(n >= 3, f.contains('3'), reason: '$where 3x');
          expect(n >= 5, f.contains('5'), reason: '$where 5x');
          expect(a.occurrencesUpTo(i + 1).length, n, reason: '$where occurrences API');
          expect(pos.halfmoves, clocks[i], reason: '$where clock');
          final fen = fens['$i'];
          if (fen != null) expect(pos.fen, fen, reason: '$where fen');
          // Claim rights: verified through the real claim API.
          if (f.contains('T') || maxCount >= 2) {
            claims++;
            expect(claimThreefold(a, i + 1), f.contains('T'), reason: '$where 9.2 claim');
          }
          if (f.contains('F') || pos.halfmoves >= 99) {
            claims++;
            expect(claimFifty(a, i + 1), f.contains('F'), reason: '$where 9.3 claim');
          }
          plies++;
        }
        final last = flags.last;
        expect(a.end != null, RegExp('[MSD57]').hasMatch(last), reason: '$id end ($last)');
      }
      // ignore: avoid_print
      print('${entry.key}: ${entry.value.length} games, $plies plies, $claims claim checks');
    }, timeout: const Timeout(Duration(minutes: 20)));
  }

  final pgnDir = Directory('$dataDir/pgn');
  if (pgnDir.existsSync()) {
    for (final file in pgnDir.listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      final expected = byFile[name];
      if (expected == null) continue;
      test('PGN reader: $name', () {
        final bytes = file.readAsBytesSync();
        String text;
        try {
          text = utf8.decode(bytes);
        } on FormatException {
          text = latin1.decode(bytes); // older German/British files
        }
        final parsed = parsePgn(text);
        for (final g in expected) {
          final idx = g['index'] as int;
          final tokens = parsed[idx].moves;
          final a = analyzeGame(tokens);
          expect(a.stopPly, isNull, reason: '$name#$idx tokens: ${tokens.take(8)}');
          expect(a.sans.join(' '), g['sans'], reason: '$name#$idx');
        }
      }, timeout: const Timeout(Duration(minutes: 10)));
    }
  }

  test('start position sanity', () => expect(Position.initial().legalMoves.length, 20));
}
