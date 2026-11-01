import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/arbiter/analysis.dart';
import 'package:mobile/core/arbiter/game_record.dart';
import 'package:mobile/core/arbiter/report.dart';
import 'package:mobile/core/chess/notation.dart';
import 'package:mobile/services/report_pdf.dart';

ByteData _font(String path) =>
    ByteData.sublistView(File(path).readAsBytesSync());

void main() {
  test('PDF report renders with Turkish glyphs', () async {
    final rec = GameRecord(
      id: 'x', createdAt: DateTime(2026), updatedAt: DateTime(2026),
      headers: const {'White': 'Şükrü Öğüt', 'Black': 'İpek Çağ'},
      tokens: 'e4 e5 Af3 Ac6 Ag1 Ag8 Af3 Ac6 Ag1 Ag8 Şe2'.split(' '),
      locale: NotationLocale.tr,
    );
    final bytes = await renderReportPdf(
      sections: buildReport(rec, analyzeGame(rec.tokens, locale: rec.locale)),
      title: 'Hakem Raporu',
      subtitle: rec.title,
      font: _font('assets/fonts/Inter.ttf'),
      mono: _font('assets/fonts/JetBrainsMono.ttf'),
    );
    expect(bytes.length, greaterThan(2000));
    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
  });
}
