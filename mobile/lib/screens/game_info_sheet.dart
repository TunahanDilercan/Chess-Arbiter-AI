import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/arbiter/game_record.dart';
import '../core/arbiter/time_control.dart';
import '../core/chess/notation.dart';
import '../providers/providers.dart';
import '../theme/arbiter_tokens.dart';
import '../widgets/desk_ui.dart';

Future<void> showGameInfoSheet(BuildContext context, GameRecord record) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _GameInfoSheet(record: record),
    ),
  );
}

class _GameInfoSheet extends ConsumerStatefulWidget {
  const _GameInfoSheet({required this.record});
  final GameRecord record;

  @override
  ConsumerState<_GameInfoSheet> createState() => _GameInfoSheetState();
}

class _GameInfoSheetState extends ConsumerState<_GameInfoSheet> {
  static const _fields = [
    ('White', 'Beyaz oyuncu'),
    ('Black', 'Siyah oyuncu'),
    ('Event', 'Turnuva'),
    ('Round', 'Tur'),
    ('Board', 'Masa'),
    ('Date', 'Tarih'),
    ('Result', 'Karnedeki sonuç (1-0, 0-1, 1/2-1/2)'),
  ];
  late final Map<String, TextEditingController> _ctl = {
    for (final (k, _) in _fields)
      k: TextEditingController(text: widget.record.headers[k] ?? ''),
  };
  late final _notes = TextEditingController(text: widget.record.notes);
  late TimeControl _tc = widget.record.timeControl;
  late NotationLocale _locale = widget.record.locale;

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final headers = {...widget.record.headers};
    for (final e in _ctl.entries) {
      final v = e.value.text.trim();
      if (v.isEmpty) {
        headers.remove(e.key);
      } else {
        headers[e.key] = v;
      }
    }
    await ref.read(gamesProvider.notifier).save(widget.record.copyWith(
          headers: headers,
          timeControl: _tc,
          locale: _locale,
          notes: _notes.text,
        ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            ArbiterSpacing.s4, 0, ArbiterSpacing.s4, ArbiterSpacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Oyun bilgileri', style: displayStyle(context, 20)),
            const SizedBox(height: ArbiterSpacing.s3),
            for (final (k, label) in _fields) ...[
              TextField(
                controller: _ctl[k],
                decoration: InputDecoration(labelText: label, isDense: true),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: ArbiterSpacing.s2),
            ],
            const SizedBox(height: ArbiterSpacing.s2),
            const SectionLabel('Tempo'),
            SegmentedButton<TimeControl>(
              segments: [
                for (final t in TimeControl.values)
                  ButtonSegment(value: t, label: Text(t.label)),
              ],
              selected: {_tc},
              onSelectionChanged: (s) => setState(() => _tc = s.first),
            ),
            const SizedBox(height: ArbiterSpacing.s3),
            const SectionLabel('Karnedeki notasyon'),
            DropdownButtonFormField<NotationLocale>(
              initialValue: _locale,
              isExpanded: true,
              items: [
                for (final l in NotationLocale.values)
                  DropdownMenuItem(
                      value: l, child: Text(l.label, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _locale = v ?? _locale),
            ),
            const SizedBox(height: ArbiterSpacing.s3),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Hakem notları'),
            ),
            const SizedBox(height: ArbiterSpacing.s4),
            FilledButton(onPressed: _save, child: const Text('Kaydet')),
          ],
        ),
      ),
    );
  }
}
