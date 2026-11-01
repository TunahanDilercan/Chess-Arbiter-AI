import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/arbiter/report.dart';

/// Renders the arbiter report as an A4 PDF. [font] must cover Turkish glyphs
/// (the bundled Inter TTF does); [mono] is used for the move list.
Future<Uint8List> renderReportPdf({
  required List<ReportSection> sections,
  required String title,
  required String subtitle,
  required ByteData font,
  required ByteData mono,
}) async {
  final base = pw.Font.ttf(font);
  final code = pw.Font.ttf(mono);
  final doc = pw.Document(title: title, author: 'Hakem Masası');
  const accent = PdfColor.fromInt(0xFFA77F50);
  const muted = PdfColor.fromInt(0xFF5A5E66);

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 48),
    theme: pw.ThemeData.withFont(base: base, bold: base),
    footer: (ctx) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('Sayfa ${ctx.pageNumber} / ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: muted)),
    ),
    build: (ctx) => [
      pw.Text(title,
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 2),
      pw.Text(subtitle, style: const pw.TextStyle(fontSize: 10, color: muted)),
      pw.Divider(color: accent, thickness: 1.2),
      for (final s in sections) ...[
        pw.SizedBox(height: 10),
        pw.Text(trUpper(s.title),
            style: const pw.TextStyle(
                fontSize: 9, color: accent, letterSpacing: 0.8)),
        pw.SizedBox(height: 4),
        for (final line in s.lines)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Text(line,
                style: pw.TextStyle(
                    fontSize: 9.5,
                    font: s.title == 'Hamleler' ? code : base,
                    lineSpacing: 1.5)),
          ),
      ],
    ],
  ));
  return doc.save();
}
