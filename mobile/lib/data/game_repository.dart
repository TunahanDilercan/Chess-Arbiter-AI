import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/arbiter/game_record.dart';

export 'file_repository_stub.dart'
    if (dart.library.io) 'file_repository_io.dart' show createFileRepository;

String newRecordId() {
  final rng = Random.secure();
  return List.generate(12, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'))
      .join();
}

/// On-device storage for game records. No server involved.
abstract class GameRepository {
  Future<List<GameRecord>> list();
  Future<void> save(GameRecord record);
  Future<void> delete(String id);
}

class MemoryGameRepository implements GameRepository {
  final _items = <String, GameRecord>{};

  @override
  Future<List<GameRecord>> list() async => _items.values.toList();
  @override
  Future<void> save(GameRecord record) async => _items[record.id] = record;
  @override
  Future<void> delete(String id) async => _items.remove(id);
}

/// SharedPreferences-backed store (web, and fallback when files are unavailable).
class PrefsGameRepository implements GameRepository {
  PrefsGameRepository(this._prefs);

  static const _kIndex = 'games_index';
  static const _kPrefix = 'game:';
  final SharedPreferences _prefs;

  @override
  Future<List<GameRecord>> list() async {
    final out = <GameRecord>[];
    for (final id in _prefs.getStringList(_kIndex) ?? const <String>[]) {
      final raw = _prefs.getString('$_kPrefix$id');
      if (raw == null) continue;
      try {
        out.add(GameRecord.fromJson(
            (jsonDecode(raw) as Map).cast<String, Object?>()));
      } on FormatException {
        continue;
      }
    }
    return out;
  }

  @override
  Future<void> save(GameRecord record) async {
    await _prefs.setString('$_kPrefix${record.id}', jsonEncode(record.toJson()));
    final ids = _prefs.getStringList(_kIndex) ?? <String>[];
    if (!ids.contains(record.id)) {
      await _prefs.setStringList(_kIndex, [...ids, record.id]);
    }
  }

  @override
  Future<void> delete(String id) async {
    await _prefs.remove('$_kPrefix$id');
    final ids = _prefs.getStringList(_kIndex) ?? <String>[];
    await _prefs.setStringList(_kIndex, ids.where((e) => e != id).toList());
  }
}
