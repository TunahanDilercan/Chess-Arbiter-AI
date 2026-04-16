// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upload.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$UploadResponseImpl _$$UploadResponseImplFromJson(Map<String, dynamic> json) =>
    _$UploadResponseImpl(
      game_id: json['game_id'] as String,
      job_id: json['job_id'] as String,
      status: json['status'] as String,
      sse_url: json['sse_url'] as String,
      game_url: json['game_url'] as String,
    );

Map<String, dynamic> _$$UploadResponseImplToJson(
  _$UploadResponseImpl instance,
) => <String, dynamic>{
  'game_id': instance.game_id,
  'job_id': instance.job_id,
  'status': instance.status,
  'sse_url': instance.sse_url,
  'game_url': instance.game_url,
};

_$JobStatusEventImpl _$$JobStatusEventImplFromJson(Map<String, dynamic> json) =>
    _$JobStatusEventImpl(
      job_id: json['job_id'] as String,
      status: json['status'] as String,
      error_message: json['error_message'] as String?,
    );

Map<String, dynamic> _$$JobStatusEventImplToJson(
  _$JobStatusEventImpl instance,
) => <String, dynamic>{
  'job_id': instance.job_id,
  'status': instance.status,
  'error_message': instance.error_message,
};

_$GameSummaryImpl _$$GameSummaryImplFromJson(Map<String, dynamic> json) =>
    _$GameSummaryImpl(
      game_id: json['game_id'] as String,
      session_id: json['session_id'] as String,
      status: json['status'] as String,
      locale: json['locale'] as String,
      created_at: json['created_at'] as String,
      total_moves: (json['total_moves'] as num?)?.toInt(),
      has_findings: json['has_findings'] as bool?,
      upload_filename: json['upload_filename'] as String?,
    );

Map<String, dynamic> _$$GameSummaryImplToJson(_$GameSummaryImpl instance) =>
    <String, dynamic>{
      'game_id': instance.game_id,
      'session_id': instance.session_id,
      'status': instance.status,
      'locale': instance.locale,
      'created_at': instance.created_at,
      'total_moves': instance.total_moves,
      'has_findings': instance.has_findings,
      'upload_filename': instance.upload_filename,
    };
