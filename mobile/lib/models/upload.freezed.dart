// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'upload.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

UploadResponse _$UploadResponseFromJson(Map<String, dynamic> json) {
  return _UploadResponse.fromJson(json);
}

/// @nodoc
mixin _$UploadResponse {
  String get game_id => throw _privateConstructorUsedError;
  String get job_id => throw _privateConstructorUsedError;
  String get status => throw _privateConstructorUsedError;
  String get sse_url => throw _privateConstructorUsedError;
  String get game_url => throw _privateConstructorUsedError;

  /// Serializes this UploadResponse to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of UploadResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $UploadResponseCopyWith<UploadResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $UploadResponseCopyWith<$Res> {
  factory $UploadResponseCopyWith(
    UploadResponse value,
    $Res Function(UploadResponse) then,
  ) = _$UploadResponseCopyWithImpl<$Res, UploadResponse>;
  @useResult
  $Res call({
    String game_id,
    String job_id,
    String status,
    String sse_url,
    String game_url,
  });
}

/// @nodoc
class _$UploadResponseCopyWithImpl<$Res, $Val extends UploadResponse>
    implements $UploadResponseCopyWith<$Res> {
  _$UploadResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of UploadResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? game_id = null,
    Object? job_id = null,
    Object? status = null,
    Object? sse_url = null,
    Object? game_url = null,
  }) {
    return _then(
      _value.copyWith(
            game_id: null == game_id
                ? _value.game_id
                : game_id // ignore: cast_nullable_to_non_nullable
                      as String,
            job_id: null == job_id
                ? _value.job_id
                : job_id // ignore: cast_nullable_to_non_nullable
                      as String,
            status: null == status
                ? _value.status
                : status // ignore: cast_nullable_to_non_nullable
                      as String,
            sse_url: null == sse_url
                ? _value.sse_url
                : sse_url // ignore: cast_nullable_to_non_nullable
                      as String,
            game_url: null == game_url
                ? _value.game_url
                : game_url // ignore: cast_nullable_to_non_nullable
                      as String,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$UploadResponseImplCopyWith<$Res>
    implements $UploadResponseCopyWith<$Res> {
  factory _$$UploadResponseImplCopyWith(
    _$UploadResponseImpl value,
    $Res Function(_$UploadResponseImpl) then,
  ) = __$$UploadResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String game_id,
    String job_id,
    String status,
    String sse_url,
    String game_url,
  });
}

/// @nodoc
class __$$UploadResponseImplCopyWithImpl<$Res>
    extends _$UploadResponseCopyWithImpl<$Res, _$UploadResponseImpl>
    implements _$$UploadResponseImplCopyWith<$Res> {
  __$$UploadResponseImplCopyWithImpl(
    _$UploadResponseImpl _value,
    $Res Function(_$UploadResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of UploadResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? game_id = null,
    Object? job_id = null,
    Object? status = null,
    Object? sse_url = null,
    Object? game_url = null,
  }) {
    return _then(
      _$UploadResponseImpl(
        game_id: null == game_id
            ? _value.game_id
            : game_id // ignore: cast_nullable_to_non_nullable
                  as String,
        job_id: null == job_id
            ? _value.job_id
            : job_id // ignore: cast_nullable_to_non_nullable
                  as String,
        status: null == status
            ? _value.status
            : status // ignore: cast_nullable_to_non_nullable
                  as String,
        sse_url: null == sse_url
            ? _value.sse_url
            : sse_url // ignore: cast_nullable_to_non_nullable
                  as String,
        game_url: null == game_url
            ? _value.game_url
            : game_url // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$UploadResponseImpl implements _UploadResponse {
  const _$UploadResponseImpl({
    required this.game_id,
    required this.job_id,
    required this.status,
    required this.sse_url,
    required this.game_url,
  });

  factory _$UploadResponseImpl.fromJson(Map<String, dynamic> json) =>
      _$$UploadResponseImplFromJson(json);

  @override
  final String game_id;
  @override
  final String job_id;
  @override
  final String status;
  @override
  final String sse_url;
  @override
  final String game_url;

  @override
  String toString() {
    return 'UploadResponse(game_id: $game_id, job_id: $job_id, status: $status, sse_url: $sse_url, game_url: $game_url)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UploadResponseImpl &&
            (identical(other.game_id, game_id) || other.game_id == game_id) &&
            (identical(other.job_id, job_id) || other.job_id == job_id) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.sse_url, sse_url) || other.sse_url == sse_url) &&
            (identical(other.game_url, game_url) ||
                other.game_url == game_url));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, game_id, job_id, status, sse_url, game_url);

  /// Create a copy of UploadResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$UploadResponseImplCopyWith<_$UploadResponseImpl> get copyWith =>
      __$$UploadResponseImplCopyWithImpl<_$UploadResponseImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$UploadResponseImplToJson(this);
  }
}

abstract class _UploadResponse implements UploadResponse {
  const factory _UploadResponse({
    required final String game_id,
    required final String job_id,
    required final String status,
    required final String sse_url,
    required final String game_url,
  }) = _$UploadResponseImpl;

  factory _UploadResponse.fromJson(Map<String, dynamic> json) =
      _$UploadResponseImpl.fromJson;

  @override
  String get game_id;
  @override
  String get job_id;
  @override
  String get status;
  @override
  String get sse_url;
  @override
  String get game_url;

  /// Create a copy of UploadResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$UploadResponseImplCopyWith<_$UploadResponseImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

JobStatusEvent _$JobStatusEventFromJson(Map<String, dynamic> json) {
  return _JobStatusEvent.fromJson(json);
}

/// @nodoc
mixin _$JobStatusEvent {
  String get job_id => throw _privateConstructorUsedError;
  String get status => throw _privateConstructorUsedError;
  String? get error_message => throw _privateConstructorUsedError;

  /// Serializes this JobStatusEvent to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of JobStatusEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $JobStatusEventCopyWith<JobStatusEvent> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $JobStatusEventCopyWith<$Res> {
  factory $JobStatusEventCopyWith(
    JobStatusEvent value,
    $Res Function(JobStatusEvent) then,
  ) = _$JobStatusEventCopyWithImpl<$Res, JobStatusEvent>;
  @useResult
  $Res call({String job_id, String status, String? error_message});
}

/// @nodoc
class _$JobStatusEventCopyWithImpl<$Res, $Val extends JobStatusEvent>
    implements $JobStatusEventCopyWith<$Res> {
  _$JobStatusEventCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of JobStatusEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? job_id = null,
    Object? status = null,
    Object? error_message = freezed,
  }) {
    return _then(
      _value.copyWith(
            job_id: null == job_id
                ? _value.job_id
                : job_id // ignore: cast_nullable_to_non_nullable
                      as String,
            status: null == status
                ? _value.status
                : status // ignore: cast_nullable_to_non_nullable
                      as String,
            error_message: freezed == error_message
                ? _value.error_message
                : error_message // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$JobStatusEventImplCopyWith<$Res>
    implements $JobStatusEventCopyWith<$Res> {
  factory _$$JobStatusEventImplCopyWith(
    _$JobStatusEventImpl value,
    $Res Function(_$JobStatusEventImpl) then,
  ) = __$$JobStatusEventImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String job_id, String status, String? error_message});
}

/// @nodoc
class __$$JobStatusEventImplCopyWithImpl<$Res>
    extends _$JobStatusEventCopyWithImpl<$Res, _$JobStatusEventImpl>
    implements _$$JobStatusEventImplCopyWith<$Res> {
  __$$JobStatusEventImplCopyWithImpl(
    _$JobStatusEventImpl _value,
    $Res Function(_$JobStatusEventImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of JobStatusEvent
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? job_id = null,
    Object? status = null,
    Object? error_message = freezed,
  }) {
    return _then(
      _$JobStatusEventImpl(
        job_id: null == job_id
            ? _value.job_id
            : job_id // ignore: cast_nullable_to_non_nullable
                  as String,
        status: null == status
            ? _value.status
            : status // ignore: cast_nullable_to_non_nullable
                  as String,
        error_message: freezed == error_message
            ? _value.error_message
            : error_message // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$JobStatusEventImpl implements _JobStatusEvent {
  const _$JobStatusEventImpl({
    required this.job_id,
    required this.status,
    this.error_message,
  });

  factory _$JobStatusEventImpl.fromJson(Map<String, dynamic> json) =>
      _$$JobStatusEventImplFromJson(json);

  @override
  final String job_id;
  @override
  final String status;
  @override
  final String? error_message;

  @override
  String toString() {
    return 'JobStatusEvent(job_id: $job_id, status: $status, error_message: $error_message)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$JobStatusEventImpl &&
            (identical(other.job_id, job_id) || other.job_id == job_id) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.error_message, error_message) ||
                other.error_message == error_message));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, job_id, status, error_message);

  /// Create a copy of JobStatusEvent
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$JobStatusEventImplCopyWith<_$JobStatusEventImpl> get copyWith =>
      __$$JobStatusEventImplCopyWithImpl<_$JobStatusEventImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$JobStatusEventImplToJson(this);
  }
}

abstract class _JobStatusEvent implements JobStatusEvent {
  const factory _JobStatusEvent({
    required final String job_id,
    required final String status,
    final String? error_message,
  }) = _$JobStatusEventImpl;

  factory _JobStatusEvent.fromJson(Map<String, dynamic> json) =
      _$JobStatusEventImpl.fromJson;

  @override
  String get job_id;
  @override
  String get status;
  @override
  String? get error_message;

  /// Create a copy of JobStatusEvent
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$JobStatusEventImplCopyWith<_$JobStatusEventImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

GameSummary _$GameSummaryFromJson(Map<String, dynamic> json) {
  return _GameSummary.fromJson(json);
}

/// @nodoc
mixin _$GameSummary {
  String get game_id => throw _privateConstructorUsedError;
  String get session_id => throw _privateConstructorUsedError;
  String get status => throw _privateConstructorUsedError;
  String get locale => throw _privateConstructorUsedError;
  String get created_at => throw _privateConstructorUsedError;
  int? get total_moves => throw _privateConstructorUsedError;
  bool? get has_findings => throw _privateConstructorUsedError;
  String? get upload_filename => throw _privateConstructorUsedError;

  /// Serializes this GameSummary to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of GameSummary
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $GameSummaryCopyWith<GameSummary> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $GameSummaryCopyWith<$Res> {
  factory $GameSummaryCopyWith(
    GameSummary value,
    $Res Function(GameSummary) then,
  ) = _$GameSummaryCopyWithImpl<$Res, GameSummary>;
  @useResult
  $Res call({
    String game_id,
    String session_id,
    String status,
    String locale,
    String created_at,
    int? total_moves,
    bool? has_findings,
    String? upload_filename,
  });
}

/// @nodoc
class _$GameSummaryCopyWithImpl<$Res, $Val extends GameSummary>
    implements $GameSummaryCopyWith<$Res> {
  _$GameSummaryCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of GameSummary
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? game_id = null,
    Object? session_id = null,
    Object? status = null,
    Object? locale = null,
    Object? created_at = null,
    Object? total_moves = freezed,
    Object? has_findings = freezed,
    Object? upload_filename = freezed,
  }) {
    return _then(
      _value.copyWith(
            game_id: null == game_id
                ? _value.game_id
                : game_id // ignore: cast_nullable_to_non_nullable
                      as String,
            session_id: null == session_id
                ? _value.session_id
                : session_id // ignore: cast_nullable_to_non_nullable
                      as String,
            status: null == status
                ? _value.status
                : status // ignore: cast_nullable_to_non_nullable
                      as String,
            locale: null == locale
                ? _value.locale
                : locale // ignore: cast_nullable_to_non_nullable
                      as String,
            created_at: null == created_at
                ? _value.created_at
                : created_at // ignore: cast_nullable_to_non_nullable
                      as String,
            total_moves: freezed == total_moves
                ? _value.total_moves
                : total_moves // ignore: cast_nullable_to_non_nullable
                      as int?,
            has_findings: freezed == has_findings
                ? _value.has_findings
                : has_findings // ignore: cast_nullable_to_non_nullable
                      as bool?,
            upload_filename: freezed == upload_filename
                ? _value.upload_filename
                : upload_filename // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$GameSummaryImplCopyWith<$Res>
    implements $GameSummaryCopyWith<$Res> {
  factory _$$GameSummaryImplCopyWith(
    _$GameSummaryImpl value,
    $Res Function(_$GameSummaryImpl) then,
  ) = __$$GameSummaryImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String game_id,
    String session_id,
    String status,
    String locale,
    String created_at,
    int? total_moves,
    bool? has_findings,
    String? upload_filename,
  });
}

/// @nodoc
class __$$GameSummaryImplCopyWithImpl<$Res>
    extends _$GameSummaryCopyWithImpl<$Res, _$GameSummaryImpl>
    implements _$$GameSummaryImplCopyWith<$Res> {
  __$$GameSummaryImplCopyWithImpl(
    _$GameSummaryImpl _value,
    $Res Function(_$GameSummaryImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of GameSummary
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? game_id = null,
    Object? session_id = null,
    Object? status = null,
    Object? locale = null,
    Object? created_at = null,
    Object? total_moves = freezed,
    Object? has_findings = freezed,
    Object? upload_filename = freezed,
  }) {
    return _then(
      _$GameSummaryImpl(
        game_id: null == game_id
            ? _value.game_id
            : game_id // ignore: cast_nullable_to_non_nullable
                  as String,
        session_id: null == session_id
            ? _value.session_id
            : session_id // ignore: cast_nullable_to_non_nullable
                  as String,
        status: null == status
            ? _value.status
            : status // ignore: cast_nullable_to_non_nullable
                  as String,
        locale: null == locale
            ? _value.locale
            : locale // ignore: cast_nullable_to_non_nullable
                  as String,
        created_at: null == created_at
            ? _value.created_at
            : created_at // ignore: cast_nullable_to_non_nullable
                  as String,
        total_moves: freezed == total_moves
            ? _value.total_moves
            : total_moves // ignore: cast_nullable_to_non_nullable
                  as int?,
        has_findings: freezed == has_findings
            ? _value.has_findings
            : has_findings // ignore: cast_nullable_to_non_nullable
                  as bool?,
        upload_filename: freezed == upload_filename
            ? _value.upload_filename
            : upload_filename // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$GameSummaryImpl implements _GameSummary {
  const _$GameSummaryImpl({
    required this.game_id,
    required this.session_id,
    required this.status,
    required this.locale,
    required this.created_at,
    this.total_moves,
    this.has_findings,
    this.upload_filename,
  });

  factory _$GameSummaryImpl.fromJson(Map<String, dynamic> json) =>
      _$$GameSummaryImplFromJson(json);

  @override
  final String game_id;
  @override
  final String session_id;
  @override
  final String status;
  @override
  final String locale;
  @override
  final String created_at;
  @override
  final int? total_moves;
  @override
  final bool? has_findings;
  @override
  final String? upload_filename;

  @override
  String toString() {
    return 'GameSummary(game_id: $game_id, session_id: $session_id, status: $status, locale: $locale, created_at: $created_at, total_moves: $total_moves, has_findings: $has_findings, upload_filename: $upload_filename)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$GameSummaryImpl &&
            (identical(other.game_id, game_id) || other.game_id == game_id) &&
            (identical(other.session_id, session_id) ||
                other.session_id == session_id) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.locale, locale) || other.locale == locale) &&
            (identical(other.created_at, created_at) ||
                other.created_at == created_at) &&
            (identical(other.total_moves, total_moves) ||
                other.total_moves == total_moves) &&
            (identical(other.has_findings, has_findings) ||
                other.has_findings == has_findings) &&
            (identical(other.upload_filename, upload_filename) ||
                other.upload_filename == upload_filename));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    game_id,
    session_id,
    status,
    locale,
    created_at,
    total_moves,
    has_findings,
    upload_filename,
  );

  /// Create a copy of GameSummary
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$GameSummaryImplCopyWith<_$GameSummaryImpl> get copyWith =>
      __$$GameSummaryImplCopyWithImpl<_$GameSummaryImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$GameSummaryImplToJson(this);
  }
}

abstract class _GameSummary implements GameSummary {
  const factory _GameSummary({
    required final String game_id,
    required final String session_id,
    required final String status,
    required final String locale,
    required final String created_at,
    final int? total_moves,
    final bool? has_findings,
    final String? upload_filename,
  }) = _$GameSummaryImpl;

  factory _GameSummary.fromJson(Map<String, dynamic> json) =
      _$GameSummaryImpl.fromJson;

  @override
  String get game_id;
  @override
  String get session_id;
  @override
  String get status;
  @override
  String get locale;
  @override
  String get created_at;
  @override
  int? get total_moves;
  @override
  bool? get has_findings;
  @override
  String? get upload_filename;

  /// Create a copy of GameSummary
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$GameSummaryImplCopyWith<_$GameSummaryImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
