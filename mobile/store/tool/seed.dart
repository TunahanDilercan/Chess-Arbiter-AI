// Builds localStorage seed data (sample games, onboarding done) for store
// screenshots of the web build:
//   dart run store/tool/seed.dart test_slow/data/pgn/<file>.pgn > seed.json

import 'dart:convert';
import 'dart:io';
import 'package:mobile/core/arbiter/game_record.dart';
import 'package:mobile/core/arbiter/sample.dart';
import 'package:mobile/core/arbiter/time_control.dart';
import 'package:mobile/core/chess/notation.dart';
import 'package:mobile/core/chess/pgn.dart';

void main(List<String> args) {
  final text = latin1.decode(File(args[0]).readAsBytesSync());
  final games = parsePgn(text).where((g) => g.moves.length > 50 && g.moves.length < 90).take(5).toList();
  final names = [
    ('Deniz Arslan', 'Kerem Öztürk', '1-0'), ('Zeynep Çelik', 'Mert Aydın', '1/2-1/2'),
    ('Selin Koç', 'Emre Şahin', '0-1'), ('Burak Demir', 'Ece Yıldız', '1-0'),
    ('Can Aksoy', 'Derin Polat', '1/2-1/2'),
  ];
  final now = DateTime(2026, 11, 1, 18, 30);
  final recs = <GameRecord>[
    GameRecord(id: 'demo', createdAt: now, updatedAt: now, headers: sampleHeaders,
        tokens: sampleTokensTr, locale: NotationLocale.tr),
    for (var i = 0; i < games.length; i++)
      GameRecord(
        id: 'g$i',
        createdAt: now.subtract(Duration(minutes: 20 * (i + 1))),
        updatedAt: now.subtract(Duration(minutes: 20 * (i + 1))),
        headers: {
          'Event': 'Örnek Açık Turnuva', 'Round': '5', 'Board': '${i + 1}',
          'White': names[i].$1, 'Black': names[i].$2, 'Result': names[i].$3,
        },
        tokens: [for (final m in games[i].moves) localizeSan(m, NotationLocale.tr)],
        locale: NotationLocale.tr,
        timeControl: i.isEven ? TimeControl.standard : TimeControl.rapid,
      ),
  ];
  final ls = <String, String>{
    'flutter.onboarded_v1': 'true',
    'flutter.games_index': jsonEncode([for (final r in recs) r.id]),
    for (final r in recs) 'flutter.game:${r.id}': jsonEncode(jsonEncode(r.toJson())),
  };
  stdout.write(jsonEncode(ls));
}
