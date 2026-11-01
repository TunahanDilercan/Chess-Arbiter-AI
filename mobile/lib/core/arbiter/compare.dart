/// Compares two scoresheets of the same game (typically White's and Black's)
/// and finds where they diverge, including a move missing from one sheet.
library;

import '../chess/notation.dart';
import '../chess/san.dart';
import 'analysis.dart';

enum RowKind { same, different, onlyA, onlyB }

class AlignedRow {
  const AlignedRow(this.kind, this.aIndex, this.bIndex, this.a, this.b);
  final RowKind kind;
  final int? aIndex;
  final int? bIndex;
  final String? a;
  final String? b;
}

class SheetComparison {
  SheetComparison({
    required this.rows,
    required this.analysisA,
    required this.analysisB,
    required this.summary,
    required this.agreedPlies,
  });

  final List<AlignedRow> rows;
  final GameAnalysis analysisA;
  final GameAnalysis analysisB;
  final List<String> summary;

  /// Number of leading plies on which both sheets agree.
  final int agreedPlies;

  bool get identical => rows.every((r) => r.kind == RowKind.same);
}

String _key(GameAnalysis a, int i) {
  final p = a.plies[i];
  return p.state.isResolved ? bareSan(p.san!) : bareSan(p.normalized);
}

SheetComparison compareSheets(
  List<String> a,
  List<String> b, {
  NotationLocale localeA = NotationLocale.en,
  NotationLocale localeB = NotationLocale.en,
}) {
  final ga = analyzeGame(a, locale: localeA);
  final gb = analyzeGame(b, locale: localeB);
  final ka = [for (var i = 0; i < a.length; i++) _key(ga, i)];
  final kb = [for (var i = 0; i < b.length; i++) _key(gb, i)];

  // Global alignment (edit distance), substitution and gaps cost 1.
  final n = ka.length, m = kb.length;
  final d = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = 0; i <= n; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= m; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final sub = d[i - 1][j - 1] + (ka[i - 1] == kb[j - 1] ? 0 : 1);
      final del = d[i - 1][j] + 1;
      final ins = d[i][j - 1] + 1;
      d[i][j] = sub < del ? (sub < ins ? sub : ins) : (del < ins ? del : ins);
    }
  }
  final rows = <AlignedRow>[];
  var i = n, j = m;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 &&
        d[i][j] == d[i - 1][j - 1] + (ka[i - 1] == kb[j - 1] ? 0 : 1)) {
      final same = ka[i - 1] == kb[j - 1];
      rows.add(AlignedRow(same ? RowKind.same : RowKind.different, i - 1, j - 1,
          a[i - 1], b[j - 1]));
      i--;
      j--;
    } else if (i > 0 && d[i][j] == d[i - 1][j] + 1) {
      rows.add(AlignedRow(RowKind.onlyA, i - 1, null, a[i - 1], null));
      i--;
    } else {
      rows.add(AlignedRow(RowKind.onlyB, null, j - 1, null, b[j - 1]));
      j--;
    }
  }
  final ordered = rows.reversed.toList();

  var agreed = 0;
  while (agreed < n && agreed < m && ka[agreed] == kb[agreed]) {
    agreed++;
  }

  final summary = <String>[];
  if (ordered.every((r) => r.kind == RowKind.same)) {
    summary.add('İki karne aynı (${a.length} yarım hamle).');
  } else {
    summary.add(agreed == 0
        ? 'Karneler ilk hamleden itibaren farklı.'
        : 'İlk ${agreed ~/ 2} tam hamle${agreed.isOdd ? ' ve Beyaz\'ın ${agreed ~/ 2 + 1}. hamlesi' : ''} '
            'iki karnede aynı.');
    for (final r in ordered) {
      switch (r.kind) {
        case RowKind.same:
          break;
        case RowKind.different:
          summary.add('${plyLabel(r.aIndex!)}: A karnesinde "${r.a}", '
              'B karnesinde "${r.b}".');
        case RowKind.onlyA:
          summary.add('B karnesinde eksik: ${plyLabel(r.aIndex!)} "${r.a}" '
              '(A karnesinde var).');
        case RowKind.onlyB:
          summary.add('A karnesinde eksik: ${plyLabel(r.bIndex!)} "${r.b}" '
              '(B karnesinde var).');
      }
      if (summary.length > 12) {
        summary.add('… diğer farklar tabloda.');
        break;
      }
    }
  }
  summary.add(_legalitySummary('A', ga));
  summary.add(_legalitySummary('B', gb));

  return SheetComparison(
    rows: ordered,
    analysisA: ga,
    analysisB: gb,
    summary: summary,
    agreedPlies: agreed,
  );
}

String _legalitySummary(String name, GameAnalysis g) {
  if (g.stopPly == null) {
    return '$name karnesi baştan sona yasal (${g.resolvedCount} yarım hamle).';
  }
  return '$name karnesi ${plyLabel(g.stopPly!)} hamlesinde takılıyor '
      '(${g.plies[g.stopPly!].raw}).';
}
