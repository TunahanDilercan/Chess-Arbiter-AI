/// Persisted game record: the scoresheet as written plus the arbiter's log.
library;

import '../chess/notation.dart';
import '../chess/types.dart';
import 'time_control.dart';

enum GameSource {
  board('Tahtada girildi'),
  pgn('PGN'),
  typed('Elle yazıldı'),
  ocr('Fotoğraftan okundu'),
  comparison('Karne karşılaştırma');

  const GameSource(this.label);
  final String label;

  static GameSource parse(String? s) =>
      values.firstWhere((v) => v.name == s, orElse: () => GameSource.typed);
}

enum LogKind {
  claim('Beraberlik talebi'),
  illegalMove('Kural dışı hamle'),
  flagFall('Süre aşımı'),
  correction('Düzeltme'),
  comparison('Karne karşılaştırma'),
  note('Not');

  const LogKind(this.label);
  final String label;

  static LogKind parse(String? s) =>
      values.firstWhere((v) => v.name == s, orElse: () => LogKind.note);
}

class ArbiterLogEntry {
  const ArbiterLogEntry({
    required this.at,
    required this.kind,
    required this.title,
    this.detail = '',
    this.ply,
    this.side,
  });

  final DateTime at;
  final LogKind kind;
  final String title;
  final String detail;
  final int? ply;
  final Side? side;

  Map<String, Object?> toJson() => {
        'at': at.toIso8601String(),
        'kind': kind.name,
        'title': title,
        'detail': detail,
        'ply': ply,
        'side': side?.name,
      };

  factory ArbiterLogEntry.fromJson(Map<String, Object?> j) => ArbiterLogEntry(
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
        kind: LogKind.parse(j['kind'] as String?),
        title: j['title'] as String? ?? '',
        detail: j['detail'] as String? ?? '',
        ply: j['ply'] as int?,
        side: switch (j['side']) {
          'white' => Side.white,
          'black' => Side.black,
          _ => null,
        },
      );
}

class GameRecord {
  const GameRecord({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.headers = const {},
    this.tokens = const [],
    this.locale = NotationLocale.en,
    this.timeControl = TimeControl.standard,
    this.source = GameSource.typed,
    this.log = const [],
    this.notes = '',
  });

  static const schemaVersion = 1;

  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, String> headers;

  /// Moves exactly as written on the scoresheet (one entry per ply).
  final List<String> tokens;
  final NotationLocale locale;
  final TimeControl timeControl;
  final GameSource source;
  final List<ArbiterLogEntry> log;
  final String notes;

  String get white => headers['White']?.trim().isNotEmpty == true
      ? headers['White']!
      : 'Beyaz';
  String get black => headers['Black']?.trim().isNotEmpty == true
      ? headers['Black']!
      : 'Siyah';
  String get event => headers['Event'] ?? '';
  String get round => headers['Round'] ?? '';
  String get board => headers['Board'] ?? '';

  String get title => '$white – $black';

  int illegalMoveCount(Side side) => log
      .where((e) => e.kind == LogKind.illegalMove && e.side == side)
      .length;

  GameRecord copyWith({
    Map<String, String>? headers,
    List<String>? tokens,
    NotationLocale? locale,
    TimeControl? timeControl,
    GameSource? source,
    List<ArbiterLogEntry>? log,
    String? notes,
    DateTime? updatedAt,
  }) =>
      GameRecord(
        id: id,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
        headers: headers ?? this.headers,
        tokens: tokens ?? this.tokens,
        locale: locale ?? this.locale,
        timeControl: timeControl ?? this.timeControl,
        source: source ?? this.source,
        log: log ?? this.log,
        notes: notes ?? this.notes,
      );

  GameRecord withLog(ArbiterLogEntry e) => copyWith(log: [...log, e]);

  Map<String, Object?> toJson() => {
        'v': schemaVersion,
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'headers': headers,
        'tokens': tokens,
        'locale': locale.name,
        'timeControl': timeControl.name,
        'source': source.name,
        'log': [for (final e in log) e.toJson()],
        'notes': notes,
      };

  factory GameRecord.fromJson(Map<String, Object?> j) {
    final now = DateTime.now();
    return GameRecord(
      id: j['id'] as String,
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? now,
      headers: {
        for (final e in ((j['headers'] as Map?) ?? const {}).entries)
          e.key.toString(): e.value.toString(),
      },
      tokens: [for (final t in (j['tokens'] as List?) ?? const []) t.toString()],
      locale: NotationLocale.parse(j['locale'] as String?),
      timeControl: TimeControl.parse(j['timeControl'] as String?),
      source: GameSource.parse(j['source'] as String?),
      log: [
        for (final e in (j['log'] as List?) ?? const [])
          ArbiterLogEntry.fromJson((e as Map).cast<String, Object?>()),
      ],
      notes: j['notes'] as String? ?? '',
    );
  }
}
