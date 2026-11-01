import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/arbiter/game_record.dart';
import '../core/arbiter/time_control.dart';
import '../core/chess/notation.dart';
import '../core/chess/pgn.dart';
import '../providers/providers.dart';
import '../theme/arbiter_tokens.dart';
import '../widgets/desk_ui.dart';
import 'board_entry_screen.dart';

class PgnImportScreen extends ConsumerStatefulWidget {
  const PgnImportScreen({super.key});

  @override
  ConsumerState<PgnImportScreen> createState() => _PgnImportScreenState();
}

class _PgnImportScreenState extends ConsumerState<PgnImportScreen> {
  final _text = TextEditingController();
  late NotationLocale _locale = ref.read(settingsProvider).locale;
  late TimeControl _tc = ref.read(settingsProvider).timeControl;
  List<PgnGame> _games = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() => _games = parsePgn(_text.text)
        .where((g) => g.moves.isNotEmpty)
        .toList()));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) _text.text = data!.text!;
  }

  Future<void> _import() async {
    if (_games.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final notifier = ref.read(gamesProvider.notifier);
      String? lastId;
      for (final g in _games) {
        if (!mounted || !await canCreateGame(context, ref)) break;
        final rec = await notifier.create(
          tokens: g.moves,
          source: GameSource.pgn,
          headers: {
            ...g.headers,
            if (g.result != null) 'Result': g.result!,
          },
          locale: _locale,
          timeControl: _tc,
        );
        lastId = rec.id;
      }
      if (!mounted || lastId == null) return;
      if (_games.length == 1) {
        context.pushReplacement('/game/$lastId');
      } else {
        showSnack(context, '${_games.length} oyun içe aktarıldı.');
        context.pop();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    return Scaffold(
      appBar: AppBar(title: const Text('PGN / metin içe aktar')),
      body: Constrained(
        child: ListView(
          padding: const EdgeInsets.all(ArbiterSpacing.s4),
          children: [
            Text(
              'PGN dosyası içeriğini veya karnedeki hamleleri yapıştırın: '
              '"1. e4 e5 2. Af3 Ac6", her satıra bir hamle ya da virgülle '
              'ayrılmış liste olabilir. Boş/okunmayan hücre için "?" yazın.',
              style: TextStyle(color: c.contentSecondary),
            ),
            const SizedBox(height: ArbiterSpacing.s3),
            TextField(
              controller: _text,
              minLines: 8,
              maxLines: 16,
              style: const TextStyle(fontFamily: ArbiterFontFamily.mono, fontSize: 14),
              decoration: InputDecoration(
                hintText: '[Event "…"]\n1. e4 e5 2. Af3 Ac6 3. Fb5 …',
                suffixIcon: IconButton(
                  tooltip: 'Panodan yapıştır',
                  icon: const Icon(Icons.content_paste),
                  onPressed: _paste,
                ),
              ),
            ),
            const SizedBox(height: ArbiterSpacing.s3),
            const SectionLabel('Karnedeki notasyon'),
            Wrap(
              spacing: 6,
              children: [
                for (final l in NotationLocale.values)
                  ChoiceChip(
                    label: Text(l.label),
                    selected: _locale == l,
                    onSelected: (_) => setState(() => _locale = l),
                  ),
              ],
            ),
            const SizedBox(height: ArbiterSpacing.s3),
            const SectionLabel('Tempo'),
            SegmentedButton<TimeControl>(
              segments: [
                for (final t in TimeControl.values) ButtonSegment(value: t, label: Text(t.label)),
              ],
              selected: {_tc},
              onSelectionChanged: (s) => setState(() => _tc = s.first),
            ),
            const SizedBox(height: ArbiterSpacing.s4),
            if (_games.isNotEmpty) ...[
              SectionLabel('${_games.length} oyun bulundu'),
              for (final g in _games.take(20))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined),
                  title: Text(
                      '${g.headers['White'] ?? 'Beyaz'} – ${g.headers['Black'] ?? 'Siyah'}'),
                  subtitle: Text('${g.moves.length} yarım hamle'
                      '${g.headers['Event'] == null ? '' : ' · ${g.headers['Event']}'}'),
                ),
            ],
            const SizedBox(height: ArbiterSpacing.s3),
            FilledButton.icon(
              onPressed: _games.isEmpty || _busy ? null : _import,
              icon: const Icon(Icons.download_done),
              label: Text(_games.length > 1 ? 'Tümünü içe aktar' : 'İçe aktar ve incele'),
            ),
          ],
        ),
      ),
    );
  }
}
