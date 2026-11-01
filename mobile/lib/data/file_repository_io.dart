import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/arbiter/game_record.dart';
import 'game_repository.dart';

/// One JSON file per game under the app's documents directory. Writes go to a
/// temporary file first and are renamed into place, so a crash never leaves a
/// half-written record.
class FileGameRepository implements GameRepository {
  FileGameRepository(this._dir);

  final Directory _dir;

  File _file(String id) => File('${_dir.path}/$id.json');

  @override
  Future<List<GameRecord>> list() async {
    if (!await _dir.exists()) return [];
    final out = <GameRecord>[];
    await for (final f in _dir.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        out.add(GameRecord.fromJson(
            (jsonDecode(await f.readAsString()) as Map).cast<String, Object?>()));
      } on FormatException {
        continue;
      }
    }
    return out;
  }

  @override
  Future<void> save(GameRecord record) async {
    await _dir.create(recursive: true);
    final tmp = File('${_dir.path}/${record.id}.json.tmp');
    await tmp.writeAsString(jsonEncode(record.toJson()), flush: true);
    await tmp.rename(_file(record.id).path);
  }

  @override
  Future<void> delete(String id) async {
    final f = _file(id);
    if (await f.exists()) await f.delete();
  }
}

Future<GameRepository?> createFileRepository() async {
  final docs = await getApplicationDocumentsDirectory();
  return FileGameRepository(Directory('${docs.path}/games'));
}
