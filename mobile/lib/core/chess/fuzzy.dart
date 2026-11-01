/// Ranks legal moves by similarity to a written (possibly misread) token.
/// Port of backend candidate_matcher: indel-ratio similarity plus a bonus for
/// edits explained by known handwriting/OCR confusions.
library;

import 'position.dart';
import 'san.dart';
import 'types.dart';

const double _wLev = 0.5;
const double _wConf = 0.4;
const double _wBonus = 0.1;

const Map<String, List<String>> _confusions = {
  'B': ['8', '3'], '8': ['B'], '3': ['B'],
  'l': ['1', 'I'], '1': ['l', 'I'], 'I': ['l', '1'],
  'O': ['0', 'Q'], '0': ['O'], 'Q': ['O', '0'],
  'N': ['M', 'H'], 'M': ['N'], 'H': ['N'],
  'R': ['K', 'P'], 'K': ['R'], 'P': ['R'],
  '5': ['S'], 'S': ['5'], '6': ['b'], 'b': ['6'],
  'c': ['e'], 'e': ['c'], 'g': ['q', '9'], '9': ['g'], 'q': ['g'],
  'h': ['b', 'n'], 'n': ['h'], 'a': ['d'], 'd': ['a'],
};

final Set<String> _pairs = {
  for (final e in _confusions.entries)
    for (final o in e.value) _pairKey(e.key, o),
};

String _pairKey(String a, String b) => a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';

/// python-Levenshtein compatible ratio: 1 - indel_distance / (|a| + |b|).
double indelRatio(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 1;
  if (a.isEmpty || b.isEmpty) return 0;
  // LCS length → indel distance = |a| + |b| - 2·lcs.
  final prev = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    var diag = 0;
    for (var j = 1; j <= b.length; j++) {
      final tmp = prev[j];
      prev[j] = a[i - 1] == b[j - 1]
          ? diag + 1
          : (prev[j] > prev[j - 1] ? prev[j] : prev[j - 1]);
      diag = tmp;
    }
  }
  final lcs = prev[b.length];
  return 2 * lcs / (a.length + b.length);
}

/// Edit operations (Levenshtein): returns list of (op, i, j).
List<(String, int, int)> editOps(String a, String b) {
  final n = a.length, m = b.length;
  final d = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = 0; i <= n; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= m; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var best = d[i - 1][j - 1] + cost;
      if (d[i - 1][j] + 1 < best) best = d[i - 1][j] + 1;
      if (d[i][j - 1] + 1 < best) best = d[i][j - 1] + 1;
      d[i][j] = best;
    }
  }
  final ops = <(String, int, int)>[];
  var i = n, j = m;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && d[i][j] == d[i - 1][j - 1] && a[i - 1] == b[j - 1]) {
      i--;
      j--;
    } else if (i > 0 && j > 0 && d[i][j] == d[i - 1][j - 1] + 1) {
      ops.add(('replace', i - 1, j - 1));
      i--;
      j--;
    } else if (i > 0 && d[i][j] == d[i - 1][j] + 1) {
      ops.add(('delete', i - 1, j));
      i--;
    } else {
      ops.add(('insert', i, j - 1));
      j--;
    }
  }
  return ops.reversed.toList();
}

double confusionBonus(String written, String candidate) {
  if (written == candidate) return 0;
  final ops = editOps(written, candidate);
  if (ops.isEmpty) return 0;
  var confused = 0;
  for (final (op, i, j) in ops) {
    if (op == 'replace' && _pairs.contains(_pairKey(written[i], candidate[j]))) {
      confused++;
    }
  }
  return confused / ops.length;
}

class RankedMove {
  const RankedMove(this.move, this.san, this.score);
  final Move move;
  final String san;
  final double score;
}

/// Legal moves of [pos] ranked by likelihood of matching [written] (already
/// normalized to English letters). Ties are broken by SAN for determinism.
List<RankedMove> rankMoves(Position pos, String written, {double confidence = 1}) {
  final w = bareSan(written);
  final out = <RankedMove>[];
  for (final m in pos.legalMoves) {
    final san = toSan(pos, m);
    final c = bareSan(san);
    final lev = indelRatio(w, c);
    final score = _wLev * lev + _wConf * confidence + _wBonus * confusionBonus(w, c);
    out.add(RankedMove(m, san, score));
  }
  out.sort((a, b) {
    final s = b.score.compareTo(a.score);
    return s != 0 ? s : a.san.compareTo(b.san);
  });
  return out;
}
