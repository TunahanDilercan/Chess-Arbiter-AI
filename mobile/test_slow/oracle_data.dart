import 'dart:convert';
import 'dart:io';

/// Loads data produced by tool/gen_oracle_suite.py (see test_slow/README.md).
const dataDir = 'test_slow/data';

bool get hasRealGames => File('$dataDir/real_games.jsonl.gz').existsSync();
bool get hasPerft => File('$dataDir/perft_positions.json.gz').existsSync();

List<Map<String, dynamic>> loadRealGames() {
  final text = utf8.decode(gzip.decode(File('$dataDir/real_games.jsonl.gz').readAsBytesSync()));
  return [
    for (final line in const LineSplitter().convert(text))
      if (line.isNotEmpty) (jsonDecode(line) as Map).cast<String, dynamic>(),
  ];
}

Map<String, dynamic> loadPerft() => (jsonDecode(utf8.decode(
            gzip.decode(File('$dataDir/perft_positions.json.gz').readAsBytesSync())))
        as Map)
    .cast<String, dynamic>();
