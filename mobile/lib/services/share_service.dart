import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../core/arbiter/analysis.dart';
import '../core/arbiter/game_record.dart';
import '../core/arbiter/report.dart';
import '../core/chess/pgn.dart';
import '../providers/providers.dart';
import '../widgets/desk_ui.dart';
import 'report_pdf.dart';

/// Standard PGN (English SAN) with the arbiter's findings as comments.
String buildPgn(GameRecord rec, GameAnalysis a) {
  final comments = <int, String>{};
  for (final e in a.events) {
    if (e.ply < 0) continue;
    final art = e.articles.isEmpty ? '' : ' (${e.articles.first.label})';
    comments.update(e.ply, (v) => '$v; ${e.title}$art', ifAbsent: () => '${e.title}$art');
  }
  final sans = a.sans;
  if (a.stopPly != null && sans.isNotEmpty) {
    final rest = rec.tokens.sublist(a.stopPly!).join(' ');
    comments.update(sans.length - 1, (v) => '$v; Karnede devamı: $rest',
        ifAbsent: () => 'Karnede devamı (çözümlenemedi): $rest');
  }
  final result = a.end?.result ?? rec.headers['Result'] ?? '*';
  return writePgn(
    headers: {
      ...rec.headers,
      'Annotator': 'Hakem Masası',
      'TimeControl': rec.headers['TimeControl'] ?? '',
    },
    sans: sans,
    result: result,
    comments: comments,
  );
}

String _fileStem(GameRecord r) {
  final base = '${r.white}-${r.black}'
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9çğıöşü]+'), '-')
      .replaceAll(RegExp('-+'), '-');
  return base.isEmpty ? 'oyun' : base;
}

Future<void> sharePgn(BuildContext context, GameRecord rec, GameAnalysis a) async {
  final pgn = buildPgn(rec, a);
  await SharePlus.instance.share(ShareParams(
    text: pgn,
    subject: '${rec.title} (PGN)',
  ));
}

Future<void> shareReportText(
    BuildContext context, WidgetRef ref, GameRecord rec, GameAnalysis a) async {
  final name = ref.read(settingsProvider).arbiterName;
  final text = reportAsText(buildReport(rec, a, arbiterName: name));
  await SharePlus.instance.share(ShareParams(text: text, subject: 'Hakem raporu — ${rec.title}'));
}

Future<void> shareReportPdf(
    BuildContext context, WidgetRef ref, GameRecord rec, GameAnalysis a) async {
  try {
    final name = ref.read(settingsProvider).arbiterName;
    final bytes = await renderReportPdf(
      sections: buildReport(rec, a, arbiterName: name),
      title: 'Hakem Raporu',
      subtitle: rec.title,
      font: await rootBundle.load('assets/fonts/Inter.ttf'),
      mono: await rootBundle.load('assets/fonts/JetBrainsMono.ttf'),
    );
    await SharePlus.instance.share(ShareParams(
      files: [
        XFile.fromData(bytes,
            mimeType: 'application/pdf', name: 'hakem-raporu-${_fileStem(rec)}.pdf'),
      ],
      fileNameOverrides: ['hakem-raporu-${_fileStem(rec)}.pdf'],
      subject: 'Hakem raporu — ${rec.title}',
    ));
  } on Exception catch (e) {
    if (context.mounted) showSnack(context, 'PDF oluşturulamadı: $e');
  }
}
