/// Minimal, forgiving PGN reader/writer. Keeps the mainline move tokens exactly
/// as written so the arbiter layer can judge them (illegal moves included).
library;

const sevenTagRoster = ['Event', 'Site', 'Date', 'Round', 'White', 'Black', 'Result'];
const pgnResults = {'1-0', '0-1', '1/2-1/2', '½-½', '*'};

class PgnGame {
  PgnGame({Map<String, String>? headers, List<String>? moves, this.result})
      : headers = headers ?? {},
        moves = moves ?? [];

  final Map<String, String> headers;
  final List<String> moves;
  String? result;
}

final _reHeader = RegExp(r'^\s*\[\s*([A-Za-z0-9_]+)\s+"((?:[^"\\]|\\.)*)"\s*\]\s*$');
final _reMoveNumber = RegExp(r'^(\d+)(\.+|\))?');

/// Parses one or more games. Also accepts bare move lists ("1.e4 e5 2.Nf3",
/// "e4, e5, Nf3", one move per line). "?" or "--" keep an unknown cell.
List<PgnGame> parsePgn(String text) {
  final games = <PgnGame>[];
  var current = PgnGame();
  var sawMoves = false;

  void finish() {
    if (sawMoves || current.headers.isNotEmpty) games.add(current);
    current = PgnGame();
    sawMoves = false;
  }

  final lines = text.replaceAll('\r\n', '\n').split('\n');
  final body = StringBuffer();
  void flushBody() {
    if (body.isEmpty) return;
    final added = _parseMovetext(body.toString(), current);
    if (added) sawMoves = true;
    body.clear();
  }

  for (final line in lines) {
    if (line.startsWith('%')) continue;
    final h = _reHeader.firstMatch(line);
    if (h != null) {
      flushBody();
      if (sawMoves) finish();
      current.headers[h.group(1)!] = h.group(2)!.replaceAll(r'\"', '"');
      continue;
    }
    body.writeln(line);
  }
  flushBody();
  finish();
  for (final g in games) {
    g.result ??= g.headers['Result'];
  }
  return games;
}

/// Returns true when the text contained moves or a game result.
bool _parseMovetext(String text, PgnGame game) {
  var added = false;
  var depth = 0;
  final token = StringBuffer();
  var i = 0;

  void emit() {
    if (token.isEmpty) return;
    var t = token.toString();
    token.clear();
    if (depth > 0) return;
    if (pgnResults.contains(t)) {
      game.result = t == '½-½' ? '1/2-1/2' : t;
      // A result alone (bye, forfeit) still terminates this game's movetext.
      added = true;
      return;
    }
    if (t.startsWith(r'$')) return;
    // Strip a leading move number glued to the move ("12.Nf3", "12...Nf6").
    final num = _reMoveNumber.firstMatch(t);
    if (num != null) {
      final rest = t.substring(num.end);
      final isCastle = RegExp(r'^0-?0').hasMatch(t);
      if (!isCastle) {
        if (rest.isEmpty) return;
        t = rest;
      }
    }
    if (t == '-' || t == '.' || t == ',') return;
    game.moves.add(t);
    added = true;
  }

  while (i < text.length) {
    final c = text[i];
    if (c == '{') {
      emit();
      final end = text.indexOf('}', i);
      i = end < 0 ? text.length : end + 1;
      continue;
    }
    if (c == ';') {
      emit();
      final end = text.indexOf('\n', i);
      i = end < 0 ? text.length : end + 1;
      continue;
    }
    if (c == '(') {
      emit();
      depth++;
    } else if (c == ')') {
      emit();
      if (depth > 0) depth--;
    } else if (c == ' ' || c == '\t' || c == '\n' || c == ',' || c == '|') {
      emit();
    } else {
      token.write(c);
    }
    i++;
  }
  emit();
  return added;
}

/// Writes a PGN with the seven tag roster first. [comments] maps a ply index
/// to a comment placed after that move.
String writePgn({
  required Map<String, String> headers,
  required List<String> sans,
  String? result,
  Map<int, String> comments = const {},
  int startPly = 0,
}) {
  final res = result ?? headers['Result'] ?? '*';
  final h = {...headers, 'Result': res};
  final sb = StringBuffer();
  for (final k in sevenTagRoster) {
    sb.writeln('[$k "${_esc(h[k] ?? (k == 'Result' ? '*' : '?'))}"]');
  }
  for (final e in h.entries) {
    if (sevenTagRoster.contains(e.key) || e.value.isEmpty) continue;
    sb.writeln('[${e.key} "${_esc(e.value)}"]');
  }
  sb.writeln();

  final words = <String>[];
  for (var i = 0; i < sans.length; i++) {
    final ply = startPly + i;
    final white = ply.isEven;
    final moveNo = ply ~/ 2 + 1;
    if (white) {
      words.add('$moveNo.');
    } else if (i == 0 || comments.containsKey(ply - 1)) {
      words.add('$moveNo...');
    }
    words.add(sans[i]);
    final c = comments[ply];
    if (c != null && c.isNotEmpty) {
      words.add('{${c.replaceAll('}', ')')}}');
    }
  }
  words.add(res);

  var line = StringBuffer();
  for (final w in words) {
    if (line.length + w.length + 1 > 79 && line.isNotEmpty) {
      sb.writeln(line.toString());
      line = StringBuffer();
    }
    if (line.isNotEmpty) line.write(' ');
    line.write(w);
  }
  if (line.isNotEmpty) sb.writeln(line.toString());
  return sb.toString();
}

String _esc(String v) => v.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
