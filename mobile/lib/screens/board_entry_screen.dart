import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/arbiter/analysis.dart';
import '../core/arbiter/game_record.dart';
import '../core/arbiter/report.dart';
import '../core/chess/fuzzy.dart';
import '../core/chess/notation.dart';
import '../core/chess/position.dart';
import '../core/chess/san.dart';
import '../core/chess/types.dart';
import '../monetization/plans.dart';
import '../providers/providers.dart';
import '../theme/arbiter_tokens.dart';
import '../widgets/analysis_panels.dart';
import '../widgets/chess_board.dart';
import '../widgets/chess_keyboard.dart';
import '../widgets/desk_ui.dart';
import '../widgets/pro_gate.dart';
import 'move_edit_sheet.dart';

/// Free-tier archive limit; Pro removes it.
Future<bool> canCreateGame(BuildContext context, WidgetRef ref) async {
  if (ref.read(entitlementProvider).isPro) return true;
  final count = ref.read(gamesProvider).valueOrNull?.length ?? 0;
  if (count < kFreeArchiveLimit) return true;
  showSnack(context,
      'Ücretsiz sürümde en fazla $kFreeArchiveLimit oyun saklanır. Eski bir oyunu silin veya Pro\'ya geçin.');
  return ensureProAccess(context, ref, ProFeature.archive);
}

enum EntryMode { board, keyboard }

class BoardEntryScreen extends ConsumerStatefulWidget {
  const BoardEntryScreen({super.key, this.gameId, this.initialMode = EntryMode.board});
  final String? gameId;
  final EntryMode initialMode;

  @override
  ConsumerState<BoardEntryScreen> createState() => _BoardEntryScreenState();
}

class _BoardEntryScreenState extends ConsumerState<BoardEntryScreen> {
  late EntryMode _mode = widget.initialMode;
  List<String> _tokens = [];
  late NotationLocale _locale;
  String? _selected;
  bool _flipped = false;
  String _input = '';
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final rec = widget.gameId == null ? null : ref.read(gameRecordProvider(widget.gameId!));
    _tokens = [...?rec?.tokens];
    _locale = rec?.locale ?? ref.read(settingsProvider).locale;
  }

  void _add(String token) => setState(() {
        HapticFeedback.selectionClick();
        _tokens.add(token);
        _selected = null;
        _input = '';
        _dirty = true;
      });

  Future<void> _onTap(Position pos, String sq) async {
    final s = Square.parse(sq)!;
    if (_selected == null) {
      if (pos.pieceAt(s)?.side == pos.turn) setState(() => _selected = sq);
      return;
    }
    final from = Square.parse(_selected!)!;
    final moves = pos.legalMoves.where((m) => m.from == from && m.to == s).toList();
    if (moves.isEmpty) {
      setState(() => _selected = pos.pieceAt(s)?.side == pos.turn ? sq : null);
      return;
    }
    var move = moves.first;
    if (moves.length > 1) {
      final role = await showDialog<Role>(
        context: context,
        builder: (_) => SimpleDialog(
          title: const Text('Terfi taşı'),
          children: [
            for (final r in const [Role.queen, Role.rook, Role.bishop, Role.knight])
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, r),
                child: Text(localizeSan(r.sanLetter, _locale),
                    style: displayStyle(context, 20)),
              ),
          ],
        ),
      );
      if (role == null) return;
      move = moves.firstWhere((m) => m.promotion == role);
    }
    _add(localizeSan(toSan(pos, move), _locale));
  }

  Future<void> _confirmTyped(Position pos) async {
    final t = _input.trim();
    if (t.isEmpty) return;
    final r = parseMove(pos, normalizeMove(t, _locale));
    if (r.isResolved) {
      _add(t);
      return;
    }
    final keep = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(r.status == SanParseStatus.ambiguous ? 'Belirsiz hamle' : 'Yasal olmayan hamle'),
        content: Text(
          '"$t" bu konumda ${r.status == SanParseStatus.ambiguous ? 'birden fazla hamleye uyuyor' : 'yasal değil'}. '
          'Karnede böyle yazıyorsa olduğu gibi ekleyebilirsiniz; uygulama bu '
          'hamlede durup hakem kararını isteyecek.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Düzelt')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Karnedeki gibi ekle')),
        ],
      ),
    );
    if (keep == true) _add(t);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final notifier = ref.read(gamesProvider.notifier);
    try {
      if (widget.gameId != null) {
        final rec = ref.read(gameRecordProvider(widget.gameId!))!;
        await notifier.save(rec.copyWith(tokens: _tokens));
        if (mounted) context.pop();
        return;
      }
      if (!await canCreateGame(context, ref)) return;
      final rec = await notifier.create(
        tokens: _tokens,
        source: _mode == EntryMode.board ? GameSource.board : GameSource.typed,
        locale: _locale,
      );
      if (mounted) context.pushReplacement('/game/${rec.id}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty || _tokens.isEmpty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Kaydedilmemiş hamleler var'),
        content: const Text('Çıkarsanız girdiğiniz hamleler kaybolur.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Kal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Çık')),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    final settings = ref.watch(settingsProvider);
    final a = analyzeGame(_tokens, locale: _locale);
    final stopped = a.stopPly != null;
    final ended = a.end != null;
    final pos = a.finalPosition;
    final targets = _selected == null
        ? <String>{}
        : {
            for (final m in pos.legalMoves)
              if (m.from == Square.parse(_selected!)) Square.name(m.to),
          };
    final last = a.plies.isEmpty ? null : a.plies.last;
    final lastMove = last?.move;
    final recentEvents = a.events.reversed.take(2).toList();

    final keyboardSuggestions = stopped || ended
        ? const <String>[]
        : () {
            final ranked = rankMoves(pos, normalizeMove(_input, _locale))
                .map((r) => localizeSan(r.san, _locale));
            final pref = ranked.where((s) => s.startsWith(_input)).toList();
            return (_input.isEmpty || pref.isEmpty ? ranked : pref).take(10).toList();
          }();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.gameId == null ? 'Yeni oyun' : 'Tahtada devam'),
          actions: [
            PopupMenuButton<NotationLocale>(
              tooltip: 'Notasyon',
              initialValue: _locale,
              onSelected: (l) => setState(() => _locale = l),
              itemBuilder: (_) => [
                for (final l in NotationLocale.values)
                  PopupMenuItem(value: l, child: Text(l.label)),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(child: Text(_locale.code, style: TextStyle(color: c.accentPrimary))),
              ),
            ),
            IconButton(
              tooltip: widget.gameId == null ? 'Kaydet ve incele' : 'Kaydet',
              onPressed: _tokens.isEmpty || _saving ? null : _save,
              icon: const Icon(Icons.check_circle),
              color: c.accentPrimary,
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(ArbiterSpacing.s3),
                children: [
                  SegmentedButton<EntryMode>(
                    segments: const [
                      ButtonSegment(
                          value: EntryMode.board,
                          icon: Icon(Icons.grid_on),
                          label: Text('Tahtada oyna')),
                      ButtonSegment(
                          value: EntryMode.keyboard,
                          icon: Icon(Icons.keyboard),
                          label: Text('Karneden yaz')),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) => setState(() {
                      _mode = s.first;
                      _selected = null;
                    }),
                  ),
                  const SizedBox(height: ArbiterSpacing.s3),
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: _mode == EntryMode.keyboard ? 240 : 440),
                      child: ChessBoard(
                        fen: pos.fen,
                        flipped: _flipped,
                        palette: settings.palette,
                        selectedSquare: _selected,
                        targetSquares: targets,
                        lastMoveFrom: lastMove == null ? null : Square.name(lastMove.from),
                        lastMoveTo: lastMove == null ? null : Square.name(lastMove.to),
                        checkSquare: pos.isCheck ? Square.name(pos.kingSquare(pos.turn)) : null,
                        onSquareTap: _mode == EntryMode.board && !stopped && !ended
                            ? (sq) => _onTap(pos, sq)
                            : null,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          stopped
                              ? 'Hamle ${plyLabel(a.stopPly!)} çözülmeden devam edilemez'
                              : ended
                                  ? analysisStatus(a)
                                  : 'Sıra: ${pos.turn.trName} · ${pos.fullmoves}. hamle',
                          style: TextStyle(
                              color: stopped ? c.feedbackDanger : c.contentSecondary),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Geri al',
                        onPressed: _tokens.isEmpty
                            ? null
                            : () => setState(() {
                                  _tokens.removeLast();
                                  _selected = null;
                                  _dirty = true;
                                }),
                        icon: const Icon(Icons.undo),
                      ),
                      IconButton(
                        tooltip: 'Tahtayı çevir',
                        onPressed: () => setState(() => _flipped = !_flipped),
                        icon: const Icon(Icons.swap_vert),
                      ),
                    ],
                  ),
                  for (final e in recentEvents)
                    Padding(
                      padding: const EdgeInsets.only(bottom: ArbiterSpacing.s2),
                      child: _LiveEvent(event: e),
                    ),
                  _MoveStrip(
                    analysis: a,
                    locale: _locale,
                    localized: settings.showLocalized,
                    onTruncate: (i) => setState(() {
                      _tokens = _tokens.sublist(0, i);
                      _dirty = true;
                    }),
                  ),
                ],
              ),
            ),
            if (_mode == EntryMode.keyboard && !ended)
              ChessKeyboard(
                currentInput: _input,
                suggestions: keyboardSuggestions,
                pieceLetters: pieceLettersFor(_locale),
                confirmLabel: 'Ekle',
                onChar: (ch) => setState(() => _input += ch),
                onSuggestion: (s) => _add(s),
                onBackspace: () => setState(() {
                  if (_input.isNotEmpty) _input = _input.substring(0, _input.length - 1);
                }),
                onClear: () => setState(() => _input = ''),
                onConfirm: () => _confirmTyped(pos),
              ),
          ],
        ),
      ),
    );
  }
}

class _LiveEvent extends StatelessWidget {
  const _LiveEvent({required this.event});
  final RuleEvent event;

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = natureStyle(context, event.nature);
    final c = context.arbiterColors;
    return DeskCard(
      color: color.withAlpha(20),
      borderColor: color.withAlpha(100),
      padding: const EdgeInsets.all(ArbiterSpacing.s3),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: ArbiterSpacing.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: color, fontSize: ArbiterFontSize.labelSm, fontWeight: ArbiterFontWeights.semibold)),
                Text(event.title, style: TextStyle(color: c.contentPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoveStrip extends StatelessWidget {
  const _MoveStrip({
    required this.analysis,
    required this.locale,
    required this.localized,
    required this.onTruncate,
  });

  final GameAnalysis analysis;
  final NotationLocale locale;
  final bool localized;
  final ValueChanged<int> onTruncate;

  @override
  Widget build(BuildContext context) {
    final c = context.arbiterColors;
    if (analysis.plies.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(ArbiterSpacing.s3),
        child: Text('Hamleler burada karne sırasıyla görünür. Bir hamleden '
            'itibaren silmek için uzun basın.',
            style: TextStyle(color: c.contentTertiary)),
      );
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final p in analysis.plies)
          GestureDetector(
            onLongPress: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text('${plyLabel(p.index)} ve sonrası silinsin mi?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil')),
                  ],
                ),
              );
              if (ok == true) onTruncate(p.index);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: p.state.isProblem ? plyColor(context, p.state).withAlpha(30) : c.surfaceInset,
                borderRadius: BorderRadius.circular(ArbiterRadii.sm),
              ),
              child: Text(
                '${p.side == Side.white ? '${p.moveNumber}.' : ''}${displayMove(p, locale, localized)}',
                style: TextStyle(
                  fontFamily: ArbiterFontFamily.mono,
                  color: plyColor(context, p.state),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
