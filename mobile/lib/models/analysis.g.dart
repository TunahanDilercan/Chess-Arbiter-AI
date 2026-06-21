// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'analysis.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$OcrCandidateImpl _$$OcrCandidateImplFromJson(Map<String, dynamic> json) =>
    _$OcrCandidateImpl(
      text: json['text'] as String,
      confidence: (json['confidence'] as num).toDouble(),
    );

Map<String, dynamic> _$$OcrCandidateImplToJson(_$OcrCandidateImpl instance) =>
    <String, dynamic>{'text': instance.text, 'confidence': instance.confidence};

_$RuleFindingImpl _$$RuleFindingImplFromJson(Map<String, dynamic> json) =>
    _$RuleFindingImpl(
      type: json['type'] as String,
      ply_index: (json['ply_index'] as num).toInt(),
      description: json['description'] as String,
      is_automatic: json['is_automatic'] as bool,
    );

Map<String, dynamic> _$$RuleFindingImplToJson(_$RuleFindingImpl instance) =>
    <String, dynamic>{
      'type': instance.type,
      'ply_index': instance.ply_index,
      'description': instance.description,
      'is_automatic': instance.is_automatic,
    };

_$GameStatsImpl _$$GameStatsImplFromJson(Map<String, dynamic> json) =>
    _$GameStatsImpl(
      total_moves: (json['total_moves'] as num).toInt(),
      auto_resolved: (json['auto_resolved'] as num).toInt(),
      manual_review_required: (json['manual_review_required'] as num).toInt(),
      illegal_moves: (json['illegal_moves'] as num).toInt(),
      ocr_avg_confidence: (json['ocr_avg_confidence'] as num).toDouble(),
    );

Map<String, dynamic> _$$GameStatsImplToJson(_$GameStatsImpl instance) =>
    <String, dynamic>{
      'total_moves': instance.total_moves,
      'auto_resolved': instance.auto_resolved,
      'manual_review_required': instance.manual_review_required,
      'illegal_moves': instance.illegal_moves,
      'ocr_avg_confidence': instance.ocr_avg_confidence,
    };

_$UploadMetadataImpl _$$UploadMetadataImplFromJson(Map<String, dynamic> json) =>
    _$UploadMetadataImpl(
      filename: json['filename'] as String?,
      uploaded_at: json['uploaded_at'] as String?,
    );

Map<String, dynamic> _$$UploadMetadataImplToJson(
  _$UploadMetadataImpl instance,
) => <String, dynamic>{
  'filename': instance.filename,
  'uploaded_at': instance.uploaded_at,
};

_$MoveAnalysisImpl _$$MoveAnalysisImplFromJson(Map<String, dynamic> json) =>
    _$MoveAnalysisImpl(
      move_number: (json['move_number'] as num).toInt(),
      ply_index: (json['ply_index'] as num).toInt(),
      color: json['color'] as String,
      ocr_raw_text: json['ocr_raw_text'] as String,
      ocr_candidates: (json['ocr_candidates'] as List<dynamic>)
          .map((e) => OcrCandidate.fromJson(e as Map<String, dynamic>))
          .toList(),
      normalized_text: json['normalized_text'] as String,
      selected_san: json['selected_san'] as String?,
      selected_uci: json['selected_uci'] as String?,
      fen_before: json['fen_before'] as String,
      fen_after: json['fen_after'] as String,
      is_legal: json['is_legal'] as bool,
      needs_manual_review: json['needs_manual_review'] as bool,
      confidence: (json['confidence'] as num).toDouble(),
      review_reasons:
          (json['review_reasons'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      fide_alerts:
          (json['fide_alerts'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      crop_image_url: json['crop_image_url'] as String?,
      check_square: json['check_square'] as String?,
    );

Map<String, dynamic> _$$MoveAnalysisImplToJson(_$MoveAnalysisImpl instance) =>
    <String, dynamic>{
      'move_number': instance.move_number,
      'ply_index': instance.ply_index,
      'color': instance.color,
      'ocr_raw_text': instance.ocr_raw_text,
      'ocr_candidates': instance.ocr_candidates,
      'normalized_text': instance.normalized_text,
      'selected_san': instance.selected_san,
      'selected_uci': instance.selected_uci,
      'fen_before': instance.fen_before,
      'fen_after': instance.fen_after,
      'is_legal': instance.is_legal,
      'needs_manual_review': instance.needs_manual_review,
      'confidence': instance.confidence,
      'review_reasons': instance.review_reasons,
      'fide_alerts': instance.fide_alerts,
      'crop_image_url': instance.crop_image_url,
      'check_square': instance.check_square,
    };

_$GameAnalysisResponseImpl _$$GameAnalysisResponseImplFromJson(
  Map<String, dynamic> json,
) => _$GameAnalysisResponseImpl(
  game_id: json['game_id'] as String,
  session_id: json['session_id'] as String,
  status: json['status'] as String,
  upload_metadata: UploadMetadata.fromJson(
    json['upload_metadata'] as Map<String, dynamic>,
  ),
  moves: (json['moves'] as List<dynamic>)
      .map((e) => MoveAnalysis.fromJson(e as Map<String, dynamic>))
      .toList(),
  findings: (json['findings'] as List<dynamic>)
      .map((e) => RuleFinding.fromJson(e as Map<String, dynamic>))
      .toList(),
  pgn: json['pgn'] as String,
  failure_point_ply: (json['failure_point_ply'] as num?)?.toInt(),
  stats: GameStats.fromJson(json['stats'] as Map<String, dynamic>),
  draw_decision: json['draw_decision'] as String? ?? 'none',
  draw_reason: json['draw_reason'] as String?,
  arbiter_must_end: json['arbiter_must_end'] as bool? ?? false,
  requires_player_claim: json['requires_player_claim'] as bool? ?? false,
);

Map<String, dynamic> _$$GameAnalysisResponseImplToJson(
  _$GameAnalysisResponseImpl instance,
) => <String, dynamic>{
  'game_id': instance.game_id,
  'session_id': instance.session_id,
  'status': instance.status,
  'upload_metadata': instance.upload_metadata,
  'moves': instance.moves,
  'findings': instance.findings,
  'pgn': instance.pgn,
  'failure_point_ply': instance.failure_point_ply,
  'stats': instance.stats,
  'draw_decision': instance.draw_decision,
  'draw_reason': instance.draw_reason,
  'arbiter_must_end': instance.arbiter_must_end,
  'requires_player_claim': instance.requires_player_claim,
};
