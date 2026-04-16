import 'package:freezed_annotation/freezed_annotation.dart';

part 'analysis.freezed.dart';
part 'analysis.g.dart';

// ── OcrCandidate ──────────────────────────────────────────────────────────────

@freezed
class OcrCandidate with _$OcrCandidate {
  const factory OcrCandidate({
    required String text,
    required double confidence,
  }) = _OcrCandidate;

  factory OcrCandidate.fromJson(Map<String, dynamic> json) =>
      _$OcrCandidateFromJson(json);
}

// ── RuleFinding ───────────────────────────────────────────────────────────────

@freezed
class RuleFinding with _$RuleFinding {
  const factory RuleFinding({
    required String type,
    required int ply_index,
    required String description,
    required bool is_automatic,
  }) = _RuleFinding;

  factory RuleFinding.fromJson(Map<String, dynamic> json) =>
      _$RuleFindingFromJson(json);
}

// ── GameStats ─────────────────────────────────────────────────────────────────

@freezed
class GameStats with _$GameStats {
  const factory GameStats({
    required int total_moves,
    required int auto_resolved,
    required int manual_review_required,
    required int illegal_moves,
    required double ocr_avg_confidence,
  }) = _GameStats;

  factory GameStats.fromJson(Map<String, dynamic> json) =>
      _$GameStatsFromJson(json);
}

// ── UploadMetadata ────────────────────────────────────────────────────────────

@freezed
class UploadMetadata with _$UploadMetadata {
  const factory UploadMetadata({
    String? filename,
    String? uploaded_at,
  }) = _UploadMetadata;

  factory UploadMetadata.fromJson(Map<String, dynamic> json) =>
      _$UploadMetadataFromJson(json);
}

// ── MoveAnalysis ──────────────────────────────────────────────────────────────

@freezed
class MoveAnalysis with _$MoveAnalysis {
  const factory MoveAnalysis({
    required int move_number,
    required int ply_index,
    required String color,
    required String ocr_raw_text,
    required List<OcrCandidate> ocr_candidates,
    required String normalized_text,
    String? selected_san,
    String? selected_uci,
    required String fen_before,
    required String fen_after,
    required bool is_legal,
    required bool needs_manual_review,
    required double confidence,
    @Default([]) List<String> review_reasons,
    @Default([]) List<String> fide_alerts,
    String? crop_image_url,
  }) = _MoveAnalysis;

  factory MoveAnalysis.fromJson(Map<String, dynamic> json) =>
      _$MoveAnalysisFromJson(json);
}

// ── GameAnalysisResponse ──────────────────────────────────────────────────────

@freezed
class GameAnalysisResponse with _$GameAnalysisResponse {
  const factory GameAnalysisResponse({
    required String game_id,
    required String session_id,
    required String status,
    required UploadMetadata upload_metadata,
    required List<MoveAnalysis> moves,
    required List<RuleFinding> findings,
    required String pgn,
    int? failure_point_ply,
    required GameStats stats,
    @Default('none') String draw_decision,
    String? draw_reason,
    @Default(false) bool arbiter_must_end,
    @Default(false) bool requires_player_claim,
  }) = _GameAnalysisResponse;

  factory GameAnalysisResponse.fromJson(Map<String, dynamic> json) =>
      _$GameAnalysisResponseFromJson(json);
}
