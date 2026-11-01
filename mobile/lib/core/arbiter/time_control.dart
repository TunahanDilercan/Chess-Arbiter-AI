import 'fide.dart';

enum TimeControl {
  standard('Klasik', 2),
  rapid('Hızlı', 1),
  blitz('Yıldırım', 1);

  const TimeControl(this.label, this.penaltyMinutes);

  final String label;

  /// Extra minutes given to the opponent for an illegal move (7.5.5) or an
  /// incorrect draw claim (9.5.3). Appendices A/B use one minute.
  final int penaltyMinutes;

  List<FideArticle> get appendixArticles => switch (this) {
        TimeControl.standard => const [],
        TimeControl.rapid => const [Fide.appendixA],
        TimeControl.blitz => const [Fide.appendixB, Fide.appendixA],
      };

  static TimeControl parse(String? s) =>
      values.firstWhere((v) => v.name == s, orElse: () => TimeControl.standard);
}
