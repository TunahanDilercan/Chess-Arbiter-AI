/// Arbiter report (Turkish) built from a record and its analysis. Plain text
/// for sharing; the PDF renderer lays out the same [ReportSection]s.
library;

import '../chess/notation.dart';
import '../chess/pgn.dart';
import 'analysis.dart';
import 'fide.dart';
import 'game_record.dart';

class ReportSection {
  const ReportSection(this.title, this.lines);
  final String title;
  final List<String> lines;
}

/// Turkish-aware uppercase (i → İ, ı → I); Dart's toUpperCase is not.
String trUpper(String s) =>
    s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

String _two(int v) => v.toString().padLeft(2, '0');
String formatDateTime(DateTime d) =>
    '${_two(d.day)}.${_two(d.month)}.${d.year} ${_two(d.hour)}:${_two(d.minute)}';

String analysisStatus(GameAnalysis a) {
  if (a.end != null) {
    final k = a.end!.kind;
    final what = switch (k) {
      RuleKind.checkmate => 'mat',
      RuleKind.stalemate => 'pat',
      RuleKind.deadPosition => 'ölü konum',
      RuleKind.fivefold => 'beş tekrar',
      RuleKind.seventyFiveMoves => '75 hamle kuralı',
      _ => k.name,
    };
    return 'Oyun kurala göre bitti: $what (${a.end!.result}).';
  }
  if (a.stopPly != null) {
    return 'İnceleme gerekli: ${plyLabel(a.stopPly!)} hamlesi çözümlenemedi.';
  }
  return 'Tüm hamleler yasal (${a.resolvedCount} yarım hamle).';
}

List<ReportSection> buildReport(GameRecord rec, GameAnalysis a,
    {String arbiterName = ''}) {
  final h = rec.headers;
  final info = <String>[
    if (rec.event.isNotEmpty) 'Turnuva: ${rec.event}',
    if (rec.round.isNotEmpty) 'Tur: ${rec.round}',
    if (rec.board.isNotEmpty) 'Masa: ${rec.board}',
    'Beyaz: ${rec.white}',
    'Siyah: ${rec.black}',
    if ((h['Date'] ?? '').isNotEmpty) 'Tarih: ${h['Date']}',
    'Tempo: ${rec.timeControl.label}',
    'Notasyon: ${rec.locale.label}',
    'Kaynak: ${rec.source.label}',
    if ((h['Result'] ?? '').isNotEmpty && h['Result'] != '*')
      'Karnedeki sonuç: ${h['Result']}',
  ];

  final findings = <String>[
    analysisStatus(a),
    for (final e in a.events)
      '• ${e.title}${e.articles.isEmpty ? '' : ' [${e.articles.map((x) => x.label).join(', ')}]'}\n  ${e.detail}',
  ];

  final reps = <String>[
    for (final g in a.repetitions.where((g) => g.occurrences.length >= 2))
      '• ${g.occurrences.length} kez: ${g.occurrences.map(positionLabel).join('; ')}',
    for (final g in a.repetitions)
      for (final nm in g.nearMisses) '  ! ${positionLabel(nm.positionIndex)} — ${nm.reason}',
  ];

  final log = <String>[
    for (final e in rec.log)
      '• ${formatDateTime(e.at)} — ${e.kind.label}: ${e.title}'
          '${e.detail.isEmpty ? '' : '\n  ${e.detail}'}',
  ];

  final moves = writePgn(
    headers: {...rec.headers},
    sans: [for (final s in a.sans) localizeSan(s, rec.locale)],
    result: a.end?.result,
  ).split('\n').where((l) => !l.startsWith('[') && l.trim().isNotEmpty).toList();
  if (a.stopPly != null) {
    final rest = rec.tokens.sublist(a.stopPly!);
    moves.add('Çözümlenemeyen kısım (karnede yazıldığı gibi, '
        '${plyLabel(a.stopPly!)} itibarıyla): ${rest.join(' ')}');
  }

  return [
    ReportSection('Oyun bilgileri', info),
    ReportSection('Kural kontrolü', findings),
    if (reps.isNotEmpty) ReportSection('Konum tekrarları', reps),
    ReportSection('Hakem kayıtları', log.isEmpty ? ['Kayıt yok.'] : log),
    ReportSection('Hamleler', moves),
    if (rec.notes.trim().isNotEmpty) ReportSection('Notlar', [rec.notes.trim()]),
    ReportSection('Açıklama', [
      'Bu rapor hakem kararına yardımcı olmak için Hakem Masası uygulamasıyla '
          'üretilmiştir; nihai karar hakeme aittir.',
      'Esas alınan kurallar: ${Fide.lawsVersion}. Madde özetleri resmî metnin '
          'yerine geçmez.',
      'Oluşturulma: ${formatDateTime(DateTime.now())}'
          '${arbiterName.isEmpty ? '' : ' — Hakem: $arbiterName'}',
    ]),
  ];
}

String reportAsText(List<ReportSection> sections, {String title = 'HAKEM RAPORU'}) {
  final sb = StringBuffer('$title\n${'=' * title.length}\n');
  for (final s in sections) {
    sb
      ..writeln()
      ..writeln(trUpper(s.title))
      ..writeln('-' * s.title.length);
    for (final l in s.lines) {
      sb.writeln(l);
    }
  }
  return sb.toString();
}
