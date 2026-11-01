// Core performance benchmark (pure Dart, AOT):
//   dart compile exe tool/bench.dart -o /tmp/bench && /tmp/bench <file.pgn>
import 'dart:convert';
import 'dart:io';

import 'package:mobile/core/arbiter/analysis.dart';
import 'package:mobile/core/chess/notation.dart';
import 'package:mobile/core/chess/pgn.dart';

void main(List<String> args) {
  final bytes = File(args.first).readAsBytesSync();
  String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    text = latin1.decode(bytes);
  }
  for (var rep = 0; rep < 3; rep++) {
    final sw = Stopwatch()..start();
    final games = parsePgn(text);
    final tParse = sw.elapsedMilliseconds;
    sw.reset();
    var plies = 0;
    var worst = 0;
    for (final g in games) {
      final one = Stopwatch()..start();
      plies += analyzeGame(g.moves, locale: NotationLocale.en).plies.length;
      if (one.elapsedMicroseconds > worst) worst = one.elapsedMicroseconds;
    }
    stdout.writeln('games=${games.length} parse=${tParse}ms '
        'analyze=${sw.elapsedMilliseconds}ms plies=$plies '
        'perPly=${(sw.elapsedMicroseconds / plies).toStringAsFixed(1)}us '
        'worstGame=${(worst / 1000).toStringAsFixed(1)}ms');
  }
}
