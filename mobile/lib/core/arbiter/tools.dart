/// Arbiter decision aids: draw-claim verification (9.2/9.3/9.5), illegal-move
/// handling (7.5), flag fall (6.9). Each returns an explained verdict with the
/// articles it relies on. They support — never replace — the arbiter.
library;

import '../chess/fuzzy.dart';
import '../chess/notation.dart';
import '../chess/position.dart';
import '../chess/san.dart';
import '../chess/types.dart';
import 'analysis.dart';
import 'fide.dart';
import 'material.dart';
import 'time_control.dart';

// ── Draw claims ───────────────────────────────────────────────────────────────

enum ClaimType {
  threefold('Üç tekrar (9.2)'),
  fiftyMoves('50 hamle (9.3)');

  const ClaimType(this.label);
  final String label;
}

class ClaimVerdict {
  ClaimVerdict({
    required this.valid,
    required this.claimant,
    required this.positionIndex,
    required this.headline,
    required this.details,
    required this.consequences,
    required this.articles,
    this.intendedSan,
    this.matchingPositions = const [],
    this.nearMisses = const [],
  });

  final bool valid;
  final Side claimant;
  final int positionIndex;
  final String headline;
  final List<String> details;
  final List<String> consequences;
  final List<FideArticle> articles;
  final String? intendedSan;
  final List<int> matchingPositions;
  final List<NearMiss> nearMisses;
}

/// Verifies a draw claim made at positions[[positionIndex]] by the player to
/// move there, optionally based on an [intendedMove] written on the scoresheet.
ClaimVerdict checkClaim(
  GameAnalysis a, {
  required int positionIndex,
  required ClaimType type,
  required TimeControl timeControl,
  String? intendedMove,
  NotationLocale locale = NotationLocale.en,
}) {
  final pos = a.positions[positionIndex];
  final claimant = pos.turn;
  final details = <String>[];
  final articles = <FideArticle>[];
  String? intendedSan;
  Position? target = pos;
  var intendedProblem = false;

  final intended = intendedMove?.trim() ?? '';
  if (intended.isNotEmpty) {
    final r = parseMove(pos, normalizeMove(intended, locale));
    if (r.isResolved) {
      intendedSan = toSan(pos, r.move!);
      target = pos.play(r.move!);
      details.add('Talep, karneye yazılan niyet edilen hamleye dayanıyor: '
          '$intendedSan.');
    } else {
      intendedProblem = true;
      target = null;
      details.add(r.status == SanParseStatus.ambiguous
          ? 'Niyet edilen hamle "$intended" belirsiz; hangi taşın oynanacağı '
              'açık değil.'
          : 'Niyet edilen hamle "$intended" bu konumda yasal değil.');
    }
  }

  var valid = false;
  var matching = <int>[];
  var misses = <NearMiss>[];

  if (type == ClaimType.threefold) {
    articles.addAll(intendedSan != null
        ? const [Fide.a9_2_1_1, Fide.a9_2_2]
        : const [Fide.a9_2_1_2, Fide.a9_2_2]);
    if (target != null) {
      final key = target.repetitionKey;
      matching = [
        for (var j = 0; j <= positionIndex; j++)
          if (a.positions[j].repetitionKey == key) j,
      ];
      final count = matching.length + (intendedSan != null ? 1 : 0);
      valid = count >= 3;
      details.add(intendedSan != null
          ? 'Hamleden sonra oluşacak konum daha önce ${matching.length} kez '
              'oluşmuş; hamleyle birlikte $count. kez oluşacak.'
          : 'Bu konum şimdiye kadar $count kez oluşmuş.');
      if (matching.isNotEmpty) {
        details.add('Oluşumlar: ${matching.map(positionLabel).join('; ')}.');
      }
      for (var j = 0; j <= positionIndex; j++) {
        final p = a.positions[j];
        if (p.repetitionKey == key) continue;
        if (p.placementFen == target.placementFen && p.turn == target.turn) {
          final why = <String>[];
          if (p.castlingFen != target.castlingFen) why.add('rok hakları farklı');
          if (p.legalEpSquare != target.legalEpSquare) {
            why.add('geçerken alma imkânı farklı');
          }
          misses.add(NearMiss(j, '${positionLabel(j)}: taşlar aynı yerde ama '
              '${why.join(', ')} — 9.2.2 gereği sayılmaz.'));
        } else if (p.placementFen == target.placementFen) {
          misses.add(NearMiss(j, '${positionLabel(j)}: taşlar aynı yerde ama '
              'hamle sırası diğer tarafta — aynı konum sayılmaz.'));
        }
      }
      if (misses.isNotEmpty) {
        details.add('Dikkat: ${misses.length} benzer konum 9.2.2 gereği '
            'sayıma dahil edilmedi.');
      }
      if (intendedSan != null && !valid) {
        final nowCount = a.occurrencesUpTo(positionIndex).length;
        if (nowCount >= 3) {
          details.add('Not: mevcut konum zaten $nowCount. kez oluşmuştu; oyuncu '
              'niyet edilen hamle yazmadan talep etseydi talep doğru olurdu.');
        }
      }
    }
  } else {
    articles.add(Fide.a9_3);
    if (target != null) {
      final clock = target.halfmoves;
      valid = clock >= 100;
      final lastReset = positionIndex + (intendedSan != null ? 1 : 0) - clock;
      details.add(intendedSan != null
          ? 'Niyet edilen hamleden sonra piyon hamlesi/alma olmadan geçen '
              'yarım hamle sayısı: $clock (gereken: 100).'
          : 'Son piyon hamlesi veya almadan bu yana geçen yarım hamle: $clock '
              '(gereken: 100).');
      if (lastReset >= 0) {
        details.add('Sayaç ${positionLabel(lastReset)} sıfırlandı.');
      }
    }
  }

  final consequences = <String>[];
  if (valid) {
    consequences.add('Talep DOĞRU: oyun hemen berabere biter (9.5.2).');
    articles.add(Fide.a9_5_2);
  } else {
    consequences.add('Talep YANLIŞ: hakem rakibin (${claimant.opposite.trName}) '
        'süresine ${timeControl.penaltyMinutes} dakika ekler; oyun devam eder (9.5.3).');
    if (intendedSan != null) {
      consequences.add('Talep niyet edilen hamleye dayandığı için $intendedSan '
          'Madde 3 ve 4 uyarınca oynanmalıdır (9.5.3).');
    } else if (intendedProblem) {
      consequences.add('Yazılan hamle yasal olmadığından oynanamaz; oyuncu başka '
          'bir yasal hamle yapar (dokunulan taş kuralı 4.3 uygulanır). Hamle '
          'belirsizse hakem oyuncuya hangi hamleyi kastettiğini sorar.');
    } else {
      consequences.add('Oyuncu hamlesini normal şekilde yapar.');
    }
    articles.add(Fide.a9_5_3);
  }
  consequences.add('Talep geri alınamaz; saat talep sırasında durdurulur (9.5.1). '
      'Oyuncu taşa dokunduysa o hamlede talep hakkını kaybeder (9.4).');
  consequences.add('Talep aynı zamanda beraberlik teklifidir: rakip, hakem '
      'incelemeyi bitirmeden kabul ederse oyun berabere biter (9.1.2.3).');
  articles.addAll(const [Fide.a9_5_1, Fide.a9_4, Fide.a9_1_2_3]);
  if (timeControl != TimeControl.standard) {
    consequences.add('${timeControl.label} oyunda oyuncular hamle kaydetmek '
        'zorunda değildir ama karneye dayalı talep haklarını kaybetmezler.');
    articles.addAll(timeControl.appendixArticles);
  }

  return ClaimVerdict(
    valid: valid,
    claimant: claimant,
    positionIndex: positionIndex,
    headline: valid
        ? '${type.label}: talep DOĞRU'
        : '${type.label}: talep YANLIŞ',
    details: details,
    consequences: consequences,
    articles: articles,
    intendedSan: intendedSan,
    matchingPositions: matching,
    nearMisses: misses,
  );
}

// ── Illegal moves ─────────────────────────────────────────────────────────────

enum IrregularityKind {
  illegalMove('Kural dışı hamle', Fide.a7_5_1),
  promotionNotReplaced('Terfide taş konmadan saate basma', Fide.a7_5_2),
  clockWithoutMove('Hamle yapmadan saate basma', Fide.a7_5_3),
  twoHands('İki elle hamle', Fide.a7_5_4);

  const IrregularityKind(this.label, this.article);
  final String label;
  final FideArticle article;
}

class IllegalMoveAdvice {
  IllegalMoveAdvice({
    required this.offender,
    required this.reinstated,
    required this.offenceNumber,
    required this.headline,
    required this.steps,
    required this.reasons,
    required this.articles,
    required this.samePieceMoves,
    required this.likelyIntended,
    required this.isLoss,
    required this.isDraw,
    required this.needsJudgement,
  });

  final Side offender;

  /// Position immediately before the irregularity (7.5.1).
  final Position reinstated;
  final int offenceNumber;
  final String headline;
  final List<String> steps;
  final List<String> reasons;
  final List<FideArticle> articles;

  /// Legal moves for the piece type named in the illegal move (touch-move
  /// guidance for 4.3 / 4.7).
  final List<String> samePieceMoves;
  final List<String> likelyIntended;
  final bool isLoss;
  final bool isDraw;
  final bool needsJudgement;
}

IllegalMoveAdvice adviseIllegalMove({
  required Position before,
  required Side offender,
  required TimeControl timeControl,
  required int previousOffences,
  IrregularityKind kind = IrregularityKind.illegalMove,
  String writtenMove = '',
  bool adequateSupervision = true,
  bool opponentHasMovedSince = false,
  NotationLocale locale = NotationLocale.en,
}) {
  final number = previousOffences + 1;
  final norm = normalizeMove(writtenMove, locale);
  final reasons = writtenMove.trim().isEmpty || kind != IrregularityKind.illegalMove
      ? <String>[]
      : explainIllegal(before, norm);
  final articles = <FideArticle>[kind.article, Fide.a7_5_5, Fide.a4_3];
  final steps = <String>[];
  var isLoss = false, isDraw = false, needsJudgement = false;

  final rapidLike = timeControl != TimeControl.standard;
  if (rapidLike && !adequateSupervision) {
    articles.addAll(timeControl.appendixArticles);
    if (opponentHasMovedSince) {
      return IllegalMoveAdvice(
        offender: offender, reinstated: before, offenceNumber: number,
        headline: 'Rakip hamlesini yaptı: kural dışı hamle geçerli kalır',
        steps: [
          '${timeControl.label} oyunda yeterli gözetim yokken rakip bir sonraki '
              'hamlesini yaptıktan sonra kural dışı hamle düzeltilemez; oyun devam '
              'eder (Ek A).',
          'Oyuncular hakem müdahalesi olmadan düzeltmede anlaşırlarsa düzeltilebilir.',
        ],
        reasons: reasons, articles: articles, samePieceMoves: const [],
        likelyIntended: const [], isLoss: false, isDraw: false,
        needsJudgement: false,
      );
    }
    steps.add('${timeControl.label} oyunda yeterli gözetim yok: hakem, rakip '
        'bir sonraki hamlesini yapmadığı için müdahale eder (Ek A).');
  }

  steps.add('Saati durdurun. Kural dışı hamleden hemen önceki konumu kurun '
      '(7.5.1). Konum belirlenemiyorsa belirlenebilen son konumdan devam edilir.');
  if (kind == IrregularityKind.promotionNotReplaced) {
    steps.add('Piyon aynı renkten bir vezirle değiştirilir (7.5.2).');
  }

  final opponent = offender.opposite;
  if (number >= 2) {
    final ability = canCheckmate(before, opponent);
    switch (ability) {
      case MateAbility.impossible:
        isDraw = true;
        steps.add('Bu ${offender.trName} için $number. kural dışı hamle. Normalde '
            'kayıp olurdu, ancak ${opponent.trName} hiçbir yasal hamle dizisiyle '
            'mat edemeyeceği için oyun BERABERE ilan edilir (7.5.5).');
      case MateAbility.possible:
        isLoss = true;
        steps.add('Bu ${offender.trName} için $number. kural dışı hamle: '
            '${offender.trName} oyunu KAYBEDER (7.5.5).');
      case MateAbility.unclear:
        isLoss = true;
        needsJudgement = true;
        steps.add('Bu ${offender.trName} için $number. kural dışı hamle: kural '
            'gereği ${offender.trName} kaybeder; ancak ${opponent.trName} '
            'tarafının mat imkânı malzemeden kesin değil. Rakip mat edemiyorsa '
            'sonuç beraberliktir — hakem konumu değerlendirmeli (7.5.5).');
    }
  } else {
    steps.add('İlk kural dışı hamle: ${opponent.trName} tarafının süresine '
        '${timeControl.penaltyMinutes} dakika eklenir (7.5.5).');
    steps.add('${offender.trName} yeni hamlesini yapar; kural dışı hamlede '
        'dokunduğu taşla mümkünse oynamalıdır (4.3, 4.7).');
  }

  final samePiece = <String>[];
  final likely = <String>[];
  if (kind == IrregularityKind.illegalMove && norm.isNotEmpty) {
    final role = _roleOf(norm);
    for (final m in before.legalMoves) {
      if (role != null && before.pieceAt(m.from)?.role == role) {
        samePiece.add(toSan(before, m));
      }
    }
    likely.addAll(rankMoves(before, norm).take(3).map((r) => r.san));
  }

  return IllegalMoveAdvice(
    offender: offender,
    reinstated: before,
    offenceNumber: number,
    headline: isDraw
        ? '$number. kural dışı hamle — oyun berabere'
        : isLoss
            ? '$number. kural dışı hamle — ${offender.trName} kaybeder'
            : '1. kural dışı hamle — rakibe +${timeControl.penaltyMinutes} dk',
    steps: steps,
    reasons: reasons,
    articles: articles,
    samePieceMoves: samePiece,
    likelyIntended: likely,
    isLoss: isLoss,
    isDraw: isDraw,
    needsJudgement: needsJudgement,
  );
}

Role? _roleOf(String norm) {
  if (norm.startsWith('O-O')) return Role.king;
  final c = norm.isEmpty ? '' : norm[0];
  if ('abcdefgh'.contains(c)) return Role.pawn;
  return Role.fromSanLetter(c);
}

// ── Flag fall ─────────────────────────────────────────────────────────────────

class FlagVerdict {
  FlagVerdict(this.result, this.headline, this.details, this.articles);
  final String result;
  final String headline;
  final List<String> details;
  final List<FideArticle> articles;
}

FlagVerdict checkFlagFall(Position pos, Side flagged) {
  final opponent = flagged.opposite;
  if (pos.isCheckmate) {
    final winner = pos.turn.opposite;
    return FlagVerdict(winner == Side.white ? '1-0' : '0-1',
        'Tahtada mat var: ${winner.trName} kazanmıştı', [
      'Mat oyunu anında bitirir; sonradan düşen bayrak sonucu değiştirmez (5.1.1).',
    ], const [Fide.a5_1_1, Fide.a6_9]);
  }
  if (pos.isStalemate) {
    return FlagVerdict('1/2-1/2', 'Tahtada pat var: berabere', [
      'Pat oyunu anında bitirir; sonradan düşen bayrak sonucu değiştirmez (5.2.1).',
    ], const [Fide.a5_2_1, Fide.a6_9]);
  }
  if (isDeadByMaterial(pos)) {
    return FlagVerdict('1/2-1/2', 'Konum zaten ölü: berabere', [
      'Bayrak düşmeden önce konum ölüydü; oyun o anda berabere bitmişti (5.2.2).',
    ], const [Fide.a5_2_2, Fide.a6_9]);
  }
  final ability = canCheckmate(pos, opponent);
  final winResult = opponent == Side.white ? '1-0' : '0-1';
  return switch (ability) {
    MateAbility.possible => FlagVerdict(
        winResult,
        '${flagged.trName} süre aşımından kaybeder',
        [mateAbilityTr(ability, opponent),
          'Rakip mat edebildiği için süresi biten oyuncu kaybeder (6.9).'],
        const [Fide.a6_9]),
    MateAbility.impossible => FlagVerdict(
        '1/2-1/2',
        'Berabere: ${opponent.trName} mat edemez',
        [mateAbilityTr(ability, opponent),
          'Süresi biten oyuncu kaybetmez; oyun berabere biter (6.9).'],
        const [Fide.a6_9]),
    MateAbility.unclear => FlagVerdict(
        '?',
        'Hakem değerlendirmesi gerekli',
        [mateAbilityTr(ability, opponent),
          'Rakip herhangi bir yasal hamle dizisiyle (yardımlı mat dahil) mat '
              'edebiliyorsa kayıp, edemiyorsa beraberlik (6.9).'],
        const [Fide.a6_9]),
  };
}
