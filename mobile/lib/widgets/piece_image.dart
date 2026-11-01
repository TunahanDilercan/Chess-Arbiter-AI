import 'package:flutter/widgets.dart';
import 'package:vector_graphics/vector_graphics.dart';

import '../theme/arbiter_tokens.dart';

/// Provides the user's piece set to every board below it.
class PieceSetScope extends InheritedWidget {
  const PieceSetScope({super.key, required this.pieceSet, required super.child});
  final PieceSet pieceSet;

  static PieceSet of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PieceSetScope>()?.pieceSet ??
      PieceSet.celtic;

  @override
  bool updateShouldNotify(PieceSetScope oldWidget) => oldWidget.pieceSet != pieceSet;
}

/// One chess piece from a precompiled vector_graphics asset. Pictures are
/// shared between all widgets showing the same piece, so a full board decodes
/// at most 12 small binaries — no SVG/XML parsing at runtime.
class PieceImage extends StatelessWidget {
  const PieceImage(this.fenChar, {super.key, this.size, this.pieceSet});

  /// FEN piece letter: uppercase white, lowercase black.
  final String fenChar;
  final double? size;
  final PieceSet? pieceSet;

  @override
  Widget build(BuildContext context) {
    final set = pieceSet ?? PieceSetScope.of(context);
    return VectorGraphic(
      loader: AssetBytesLoader(set.asset(fenChar)),
      width: size,
      height: size,
      excludeFromSemantics: true,
    );
  }
}
