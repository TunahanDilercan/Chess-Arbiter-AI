import 'package:freezed_annotation/freezed_annotation.dart';

part 'upload.freezed.dart';
part 'upload.g.dart';

// ── UploadResponse ────────────────────────────────────────────────────────────

@freezed
class UploadResponse with _$UploadResponse {
  const factory UploadResponse({
    required String game_id,
    required String job_id,
    required String status,
    required String sse_url,
    required String game_url,
  }) = _UploadResponse;

  factory UploadResponse.fromJson(Map<String, dynamic> json) =>
      _$UploadResponseFromJson(json);
}

// ── JobStatusEvent ────────────────────────────────────────────────────────────

@freezed
class JobStatusEvent with _$JobStatusEvent {
  const factory JobStatusEvent({
    required String job_id,
    required String status,
    String? error_message,
  }) = _JobStatusEvent;

  factory JobStatusEvent.fromJson(Map<String, dynamic> json) =>
      _$JobStatusEventFromJson(json);
}

// ── GameSummary ───────────────────────────────────────────────────────────────

@freezed
class GameSummary with _$GameSummary {
  const factory GameSummary({
    required String game_id,
    required String session_id,
    required String status,
    required String locale,
    required String created_at,
    int? total_moves,
    bool? has_findings,
    String? upload_filename,
  }) = _GameSummary;

  factory GameSummary.fromJson(Map<String, dynamic> json) =>
      _$GameSummaryFromJson(json);
}
