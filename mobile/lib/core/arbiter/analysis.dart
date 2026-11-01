/// Replays a scoresheet (list of written move tokens) and produces a per-ply
/// verdict plus a timeline of FIDE events. Raw tokens are never discarded:
/// after the first unresolved move the rest stay visible as "not reached".
library;

import '../chess/fuzzy.dart';
import '../chess/notation.dart';
import '../chess/position.dart';
import '../chess/san.dart';
import '../chess/types.dart';
import 'fide.dart';
import 'material.dart';

enum PlyState {
  ok,
  notationWarning,
  ambiguous,
  illegal,
  unparseable,
  empty,

  /// After an earlier unresolved move — cannot be judged yet.
  notReached,

  /// Written after the game had already ended by rule.
  afterGameEnd;

  bool get isResolved => this == ok || this == notationWarning;
  bool get isProblem =>
      this == ambiguous || this == illegal || this == unparseable || this == empty;
}

class PlyAnalysis {
  PlyAnalysis({
    required this.index,
    required this.raw,
    required this.normalized,
    required this.state,
    required this.before,
    this.move,
    this.san,
    this.after,
    this.warnings = const [],
    this.reasons = const [],
    this.suggestions = const [],
    this.ambiguousCandidates = const [],
  });

  final int index;
  final String raw;
  final String normalized;
  final PlyState state;
  final Position before;
  final Move? move;
  final String? san;
  final Position? after;
  final List<String> warnings;
  final List<String> reasons;
  final List<RankedMove> suggestions;
  final List<String> ambiguousCandidates;

  Side get side => index.isEven ? Side.white : Side.black;
  int get moveNumber => index ~/ 2 + 1;

  /// "12." for white, "12…" for black.
  String get label => '$moveNumber${side == Side.white ? '.' : '…'}';
}

enum RuleKind {
  checkmate,
  stalemate,
  deadPosition,
  threefold,
  fivefold,
  fiftyMoves,
  seventyFiveMoves,
  illegalMove,
  ambiguousMove,
  unreadableMove,
  missingMove,
  movesAfterEnd,
}

enum RuleNature {
  /// The game ends by rule; the arbiter must stop it.
  automaticEnd,

  /// A player may claim; the game does NOT end by itself.
  claimable,

  /// Scoresheet/move problem requiring the arbiter's decision.
  error,
  info,
}

class RuleEvent {
  const RuleEvent({
    required this.kind,
    required this.nature,
    required this.ply,
    required this.title,
    required this.detail,
    this.articles = const [],
    this.positionIndices = const [],
  });

  final RuleKind kind;
  final RuleNature nature;

  /// Ply index of the move after which the event occurs (-1 = start).
  final int ply;
  final String title;
  final String detail;
  final List<FideArticle> articles;

  /// Related position indices (0 = start, i+1 = after ply i).
  final List<int> positionIndices;
}

class GameEnd {
  const GameEnd(this.kind, this.ply, this.result);
  final RuleKind kind;
  final int ply;
  final String result;
}

class NearMiss {
  const NearMiss(this.positionIndex, this.reason);
  final int positionIndex;
  final String reason;
}

class RepetitionGroup {
  RepetitionGroup(this.key, this.occurrences, this.nearMisses);
  final String key;

  /// Position indices where this exact (9.2.2) position occurred.
  final List<int> occurrences;

  /// Same piece placement and side to move, but not "the same position".
  final List<NearMiss> nearMisses;
}

class GameAnalysis {
  GameAnalysis({
    required this.plies,
    required this.positions,
    required this.events,
    required this.repetitions,
    this.stopPly,
    this.end,
  });

  final List<PlyAnalysis> plies;

  /// positions[0] = start, positions[i + 1] = after resolved ply i.
  final List<Position> positions;
  final List<RuleEvent> events;
  final List<RepetitionGroup> repetitions;

  /// First ply that could not be resolved, if any.
  final int? stopPly;
  final GameEnd? end;

  int get resolvedCount => positions.length - 1;
  Position get finalPosition => positions.last;
  List<String> get sans => [
        for (final p in plies)
          if (p.state.isResolved) p.san!,
      ];
  bool get hasProblems => stopPly != null;

  List<RuleEvent> eventsAt(int ply) => events.where((e) => e.ply == ply).toList();

  /// Positions identical (9.2.2) to positions[index] up to and including it.
  List<int> occurrencesUpTo(int index) {
    final key = positions[index].repetitionKey;
    return [
      for (var j = 0; j <= index; j++)
        if (positions[j].repetitionKey == key) j,
    ];
  }
}

/// Human label for a position index: "Başlangıç" or "12. Beyaz hamlesinden sonra".
String positionLabel(int index) {
  if (index == 0) return 'Başlangıç konumu';
  final ply = index - 1;
  final side = ply.isEven ? 'Beyaz' : 'Siyah';
  return '${ply ~/ 2 + 1}. hamle ($side) sonrası';
}

String plyLabel(int ply) =>
    '${ply ~/ 2 + 1}.${ply.isEven ? '' : '..'} ${ply.isEven ? 'Beyaz' : 'Siyah'}';

GameAnalysis analyzeGame(
  List<String> tokens, {
  NotationLocale locale = NotationLocale.en,
  String? startFen,
}) {
  var pos = startFen == null ? Position.initial() : Position.fromFen(startFen);
  final positions = <Position>[pos];
  final plies = <PlyAnalysis>[];
  final events = <RuleEvent>[];
  final seen = <String, List<int>>{pos.repetitionKey: [0]};
  int? stopPly;
  GameEnd? end;

  for (var i = 0; i < tokens.length; i++) {
    final raw = tokens[i];
    final norm = normalizeMove(raw, locale);
    if (end != null) {
      plies.add(PlyAnalysis(
          index: i, raw: raw, normalized: norm,
          state: PlyState.afterGameEnd, before: pos));
      continue;
    }
    if (stopPly != null) {
      plies.add(PlyAnalysis(
          index: i, raw: raw, normalized: norm,
          state: PlyState.notReached, before: pos));
      continue;
    }

    final r = parseMove(pos, norm);
    final label = plyLabel(i);
    switch (r.status) {
      case SanParseStatus.exact:
      case SanParseStatus.notationWarning:
        final san = toSan(pos, r.move!);
        final after = pos.play(r.move!);
        plies.add(PlyAnalysis(
          index: i, raw: raw, normalized: norm,
          state: r.status == SanParseStatus.exact
              ? PlyState.ok
              : PlyState.notationWarning,
          before: pos, move: r.move, san: san, after: after,
          warnings: r.warnings,
        ));
        positions.add(after);
        final idx = positions.length - 1;
        (seen[after.repetitionKey] ??= []).add(idx);
        end = _ruleEvents(after, i, idx, seen[after.repetitionKey]!, events);
        pos = after;
      case SanParseStatus.ambiguous:
        stopPly = i;
        final cands = [for (final m in r.candidates) toSan(pos, m)];
        plies.add(PlyAnalysis(
          index: i, raw: raw, normalized: norm, state: PlyState.ambiguous,
          before: pos, ambiguousCandidates: cands,
        ));
        events.add(RuleEvent(
          kind: RuleKind.ambiguousMove, nature: RuleNature.error, ply: i,
          title: '$label: belirsiz hamle "$raw"',
          detail: 'Yazılan hamle birden fazla yasal hamleye uyuyor: '
              '${cands.join(', ')}. Hangisinin oynandığına hakem karar vermeli '
              '(gerekirse oyuncuların karneleri karşılaştırılır).',
        ));
      case SanParseStatus.illegal:
        stopPly = i;
        final reasons = explainIllegal(pos, norm);
        plies.add(PlyAnalysis(
          index: i, raw: raw, normalized: norm, state: PlyState.illegal,
          before: pos, reasons: reasons,
          suggestions: rankMoves(pos, norm).take(5).toList(),
        ));
        events.add(RuleEvent(
          kind: RuleKind.illegalMove, nature: RuleNature.error, ply: i,
          title: '$label: kural dışı hamle "$raw"',
          detail: '${reasons.join(' ')} Bu bir yazım hatası olabileceği gibi '
              'tahtada oynanmış kural dışı bir hamle de olabilir.',
          articles: const [Fide.a7_5_1, Fide.a7_5_5],
        ));
      case SanParseStatus.unparseable:
        stopPly = i;
        plies.add(PlyAnalysis(
          index: i, raw: raw, normalized: norm, state: PlyState.unparseable,
          before: pos, reasons: const ['Notasyon tanınamadı.'],
          suggestions: rankMoves(pos, norm).take(5).toList(),
        ));
        events.add(RuleEvent(
          kind: RuleKind.unreadableMove, nature: RuleNature.error, ply: i,
          title: '$label: okunamayan hamle "$raw"',
          detail: 'Yazı satranç notasyonu olarak tanınamadı. Doğru hamleyi '
              'seçerek düzeltin.',
        ));
      case SanParseStatus.empty:
        stopPly = i;
        plies.add(PlyAnalysis(
          index: i, raw: raw, normalized: norm, state: PlyState.empty,
          before: pos,
        ));
        events.add(RuleEvent(
          kind: RuleKind.missingMove, nature: RuleNature.error, ply: i,
          title: '$label: boş / bilinmeyen hamle',
          detail: 'Karnede bu hücre boş. Oyun ancak bu hamle belirlenince '
              'devam ettirilebilir.',
        ));
    }
  }

  if (end != null) {
    final extra = plies.where((p) => p.state == PlyState.afterGameEnd).length;
    if (extra > 0) {
      events.add(RuleEvent(
        kind: RuleKind.movesAfterEnd, nature: RuleNature.info, ply: end.ply,
        title: 'Oyun bittikten sonra $extra yarım hamle yazılmış',
        detail: 'Oyun ${plyLabel(end.ply)} hamlesiyle kurala göre sona erdi; '
            'sonraki hamleler geçersizdir ve sonucu değiştirmez.',
      ));
    }
  }

  return GameAnalysis(
    plies: plies,
    positions: positions,
    events: events,
    repetitions: _repetitions(positions),
    stopPly: stopPly,
    end: end,
  );
}

GameEnd? _ruleEvents(Position after, int ply, int posIndex, List<int> occurrences,
    List<RuleEvent> events) {
  final mover = ply.isEven ? Side.white : Side.black;
  final toMove = mover.opposite;
  final label = plyLabel(ply);

  if (after.isCheckmate) {
    events.add(RuleEvent(
      kind: RuleKind.checkmate, nature: RuleNature.automaticEnd, ply: ply,
      title: '$label: mat — ${mover.trName} kazanır',
      detail: 'Oyun mat ile sona erdi.',
      articles: const [Fide.a5_1_1],
    ));
    return GameEnd(RuleKind.checkmate, ply, mover == Side.white ? '1-0' : '0-1');
  }
  if (after.isStalemate) {
    events.add(RuleEvent(
      kind: RuleKind.stalemate, nature: RuleNature.automaticEnd, ply: ply,
      title: '$label: pat — berabere',
      detail: '${toMove.trName} tarafının yasal hamlesi yok ve şahı şah altında değil.',
      articles: const [Fide.a5_2_1],
    ));
    return GameEnd(RuleKind.stalemate, ply, '1/2-1/2');
  }
  if (isDeadByMaterial(after)) {
    events.add(RuleEvent(
      kind: RuleKind.deadPosition, nature: RuleNature.automaticEnd, ply: ply,
      title: '$label: ölü konum (yetersiz malzeme) — berabere',
      detail: 'Hiçbir taraf hiçbir yasal hamle dizisiyle mat edemez. Oyun bu '
          'hamleyle kendiliğinden berabere biter; talep gerekmez.',
      articles: const [Fide.a5_2_2],
    ));
    return GameEnd(RuleKind.deadPosition, ply, '1/2-1/2');
  }
  final occText = occurrences.map(positionLabel).join('; ');
  if (occurrences.length >= 5) {
    events.add(RuleEvent(
      kind: RuleKind.fivefold, nature: RuleNature.automaticEnd, ply: ply,
      title: '$label: beş tekrar — OTOMATİK beraberlik',
      detail: 'Aynı konum 5. kez oluştu ($occText). Oyun talep beklenmeden '
          'berabere biter; hakem oyunu durdurmalı.',
      articles: const [Fide.a9_6_1, Fide.a9_2_2],
      positionIndices: occurrences,
    ));
    return GameEnd(RuleKind.fivefold, ply, '1/2-1/2');
  }
  if (after.halfmoves >= 150) {
    events.add(RuleEvent(
      kind: RuleKind.seventyFiveMoves, nature: RuleNature.automaticEnd, ply: ply,
      title: '$label: 75 hamle kuralı — OTOMATİK beraberlik',
      detail: 'Her iki taraf 75 hamledir piyon oynamadı ve alma yapmadı. Oyun '
          'talep beklenmeden berabere biter (son hamle mat olsaydı mat geçerli '
          'olurdu).',
      articles: const [Fide.a9_6_2],
      positionIndices: [posIndex - after.halfmoves, posIndex],
    ));
    return GameEnd(RuleKind.seventyFiveMoves, ply, '1/2-1/2');
  }
  if (occurrences.length >= 3) {
    events.add(RuleEvent(
      kind: RuleKind.threefold, nature: RuleNature.claimable, ply: ply,
      title: '$label: üç tekrar talep edilebilir '
          '(${occurrences.length}. oluşum)',
      detail: 'Aynı konum ${occurrences.length}. kez oluştu ($occText). '
          '${mover.trName}, bu hamleyi oynamadan önce karneye yazıp hakeme '
          'bildirerek talep edebilirdi (9.2.1.1). Şimdi sırası gelen '
          '${toMove.trName} hamle yapmadan talep edebilir (9.2.1.2). Talep '
          'edilmezse oyun DEVAM EDER.',
      articles: const [Fide.a9_2_1_1, Fide.a9_2_1_2, Fide.a9_2_2],
      positionIndices: occurrences,
    ));
  }
  if (after.halfmoves == 100) {
    events.add(RuleEvent(
      kind: RuleKind.fiftyMoves, nature: RuleNature.claimable, ply: ply,
      title: '$label: 50 hamle kuralı talep edilebilir',
      detail: 'Son 50 hamlede (her iki taraf) piyon oynanmadı, alma yapılmadı. '
          '${mover.trName} bu hamleyi yazıp bildirerek, sırası gelen '
          '${toMove.trName} ise şimdi talep edebilir. Bu hak bir piyon hamlesi '
          'veya alma yapılana kadar her hamlede sürer. Talep edilmezse oyun '
          'DEVAM EDER; 75 hamlede otomatik beraberlik olur.',
      articles: const [Fide.a9_3],
      positionIndices: [posIndex - 100, posIndex],
    ));
  }
  return null;
}

List<RepetitionGroup> _repetitions(List<Position> positions) {
  final byKey = <String, List<int>>{};
  final byPlacement = <String, List<int>>{};
  for (var i = 0; i < positions.length; i++) {
    (byKey[positions[i].repetitionKey] ??= []).add(i);
    final p = positions[i];
    (byPlacement['${p.placementFen} ${p.turn.name}'] ??= []).add(i);
  }
  final groups = <RepetitionGroup>[];
  for (final e in byKey.entries) {
    final first = positions[e.value.first];
    final placementKey = '${first.placementFen} ${first.turn.name}';
    final misses = <NearMiss>[];
    for (final j in byPlacement[placementKey]!) {
      if (e.value.contains(j)) continue;
      final other = positions[j];
      final why = <String>[];
      if (other.castlingFen != first.castlingFen) {
        why.add('rok hakları farklı (${first.castlingFen} / ${other.castlingFen})');
      }
      if (other.legalEpSquare != first.legalEpSquare) {
        why.add('geçerken alma imkânı farklı');
      }
      misses.add(NearMiss(j, 'Taşlar aynı yerde ama ${why.join(', ')} — 9.2.2 '
          'uyarınca aynı konum sayılmaz.'));
    }
    if (e.value.length >= 2 || e.value.length + misses.length >= 3) {
      groups.add(RepetitionGroup(e.key, e.value, misses));
    }
  }
  groups.sort((a, b) {
    final c = b.occurrences.length.compareTo(a.occurrences.length);
    return c != 0 ? c : a.occurrences.first.compareTo(b.occurrences.first);
  });
  return groups;
}
