// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'analysis.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

OcrCandidate _$OcrCandidateFromJson(Map<String, dynamic> json) {
  return _OcrCandidate.fromJson(json);
}

/// @nodoc
mixin _$OcrCandidate {
  String get text => throw _privateConstructorUsedError;
  double get confidence => throw _privateConstructorUsedError;

  /// Serializes this OcrCandidate to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of OcrCandidate
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $OcrCandidateCopyWith<OcrCandidate> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OcrCandidateCopyWith<$Res> {
  factory $OcrCandidateCopyWith(
    OcrCandidate value,
    $Res Function(OcrCandidate) then,
  ) = _$OcrCandidateCopyWithImpl<$Res, OcrCandidate>;
  @useResult
  $Res call({String text, double confidence});
}

/// @nodoc
class _$OcrCandidateCopyWithImpl<$Res, $Val extends OcrCandidate>
    implements $OcrCandidateCopyWith<$Res> {
  _$OcrCandidateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of OcrCandidate
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? text = null, Object? confidence = null}) {
    return _then(
      _value.copyWith(
            text: null == text
                ? _value.text
                : text // ignore: cast_nullable_to_non_nullable
                      as String,
            confidence: null == confidence
                ? _value.confidence
                : confidence // ignore: cast_nullable_to_non_nullable
                      as double,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$OcrCandidateImplCopyWith<$Res>
    implements $OcrCandidateCopyWith<$Res> {
  factory _$$OcrCandidateImplCopyWith(
    _$OcrCandidateImpl value,
    $Res Function(_$OcrCandidateImpl) then,
  ) = __$$OcrCandidateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String text, double confidence});
}

/// @nodoc
class __$$OcrCandidateImplCopyWithImpl<$Res>
    extends _$OcrCandidateCopyWithImpl<$Res, _$OcrCandidateImpl>
    implements _$$OcrCandidateImplCopyWith<$Res> {
  __$$OcrCandidateImplCopyWithImpl(
    _$OcrCandidateImpl _value,
    $Res Function(_$OcrCandidateImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of OcrCandidate
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? text = null, Object? confidence = null}) {
    return _then(
      _$OcrCandidateImpl(
        text: null == text
            ? _value.text
            : text // ignore: cast_nullable_to_non_nullable
                  as String,
        confidence: null == confidence
            ? _value.confidence
            : confidence // ignore: cast_nullable_to_non_nullable
                  as double,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$OcrCandidateImpl implements _OcrCandidate {
  const _$OcrCandidateImpl({required this.text, required this.confidence});

  factory _$OcrCandidateImpl.fromJson(Map<String, dynamic> json) =>
      _$$OcrCandidateImplFromJson(json);

  @override
  final String text;
  @override
  final double confidence;

  @override
  String toString() {
    return 'OcrCandidate(text: $text, confidence: $confidence)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OcrCandidateImpl &&
            (identical(other.text, text) || other.text == text) &&
            (identical(other.confidence, confidence) ||
                other.confidence == confidence));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, text, confidence);

  /// Create a copy of OcrCandidate
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OcrCandidateImplCopyWith<_$OcrCandidateImpl> get copyWith =>
      __$$OcrCandidateImplCopyWithImpl<_$OcrCandidateImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$OcrCandidateImplToJson(this);
  }
}

abstract class _OcrCandidate implements OcrCandidate {
  const factory _OcrCandidate({
    required final String text,
    required final double confidence,
  }) = _$OcrCandidateImpl;

  factory _OcrCandidate.fromJson(Map<String, dynamic> json) =
      _$OcrCandidateImpl.fromJson;

  @override
  String get text;
  @override
  double get confidence;

  /// Create a copy of OcrCandidate
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OcrCandidateImplCopyWith<_$OcrCandidateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

RuleFinding _$RuleFindingFromJson(Map<String, dynamic> json) {
  return _RuleFinding.fromJson(json);
}

/// @nodoc
mixin _$RuleFinding {
  String get type => throw _privateConstructorUsedError;
  int get ply_index => throw _privateConstructorUsedError;
  String get description => throw _privateConstructorUsedError;
  bool get is_automatic => throw _privateConstructorUsedError;

  /// Serializes this RuleFinding to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of RuleFinding
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $RuleFindingCopyWith<RuleFinding> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $RuleFindingCopyWith<$Res> {
  factory $RuleFindingCopyWith(
    RuleFinding value,
    $Res Function(RuleFinding) then,
  ) = _$RuleFindingCopyWithImpl<$Res, RuleFinding>;
  @useResult
  $Res call({
    String type,
    int ply_index,
    String description,
    bool is_automatic,
  });
}

/// @nodoc
class _$RuleFindingCopyWithImpl<$Res, $Val extends RuleFinding>
    implements $RuleFindingCopyWith<$Res> {
  _$RuleFindingCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of RuleFinding
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? type = null,
    Object? ply_index = null,
    Object? description = null,
    Object? is_automatic = null,
  }) {
    return _then(
      _value.copyWith(
            type: null == type
                ? _value.type
                : type // ignore: cast_nullable_to_non_nullable
                      as String,
            ply_index: null == ply_index
                ? _value.ply_index
                : ply_index // ignore: cast_nullable_to_non_nullable
                      as int,
            description: null == description
                ? _value.description
                : description // ignore: cast_nullable_to_non_nullable
                      as String,
            is_automatic: null == is_automatic
                ? _value.is_automatic
                : is_automatic // ignore: cast_nullable_to_non_nullable
                      as bool,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$RuleFindingImplCopyWith<$Res>
    implements $RuleFindingCopyWith<$Res> {
  factory _$$RuleFindingImplCopyWith(
    _$RuleFindingImpl value,
    $Res Function(_$RuleFindingImpl) then,
  ) = __$$RuleFindingImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String type,
    int ply_index,
    String description,
    bool is_automatic,
  });
}

/// @nodoc
class __$$RuleFindingImplCopyWithImpl<$Res>
    extends _$RuleFindingCopyWithImpl<$Res, _$RuleFindingImpl>
    implements _$$RuleFindingImplCopyWith<$Res> {
  __$$RuleFindingImplCopyWithImpl(
    _$RuleFindingImpl _value,
    $Res Function(_$RuleFindingImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of RuleFinding
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? type = null,
    Object? ply_index = null,
    Object? description = null,
    Object? is_automatic = null,
  }) {
    return _then(
      _$RuleFindingImpl(
        type: null == type
            ? _value.type
            : type // ignore: cast_nullable_to_non_nullable
                  as String,
        ply_index: null == ply_index
            ? _value.ply_index
            : ply_index // ignore: cast_nullable_to_non_nullable
                  as int,
        description: null == description
            ? _value.description
            : description // ignore: cast_nullable_to_non_nullable
                  as String,
        is_automatic: null == is_automatic
            ? _value.is_automatic
            : is_automatic // ignore: cast_nullable_to_non_nullable
                  as bool,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$RuleFindingImpl implements _RuleFinding {
  const _$RuleFindingImpl({
    required this.type,
    required this.ply_index,
    required this.description,
    required this.is_automatic,
  });

  factory _$RuleFindingImpl.fromJson(Map<String, dynamic> json) =>
      _$$RuleFindingImplFromJson(json);

  @override
  final String type;
  @override
  final int ply_index;
  @override
  final String description;
  @override
  final bool is_automatic;

  @override
  String toString() {
    return 'RuleFinding(type: $type, ply_index: $ply_index, description: $description, is_automatic: $is_automatic)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$RuleFindingImpl &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.ply_index, ply_index) ||
                other.ply_index == ply_index) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.is_automatic, is_automatic) ||
                other.is_automatic == is_automatic));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, type, ply_index, description, is_automatic);

  /// Create a copy of RuleFinding
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$RuleFindingImplCopyWith<_$RuleFindingImpl> get copyWith =>
      __$$RuleFindingImplCopyWithImpl<_$RuleFindingImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$RuleFindingImplToJson(this);
  }
}

abstract class _RuleFinding implements RuleFinding {
  const factory _RuleFinding({
    required final String type,
    required final int ply_index,
    required final String description,
    required final bool is_automatic,
  }) = _$RuleFindingImpl;

  factory _RuleFinding.fromJson(Map<String, dynamic> json) =
      _$RuleFindingImpl.fromJson;

  @override
  String get type;
  @override
  int get ply_index;
  @override
  String get description;
  @override
  bool get is_automatic;

  /// Create a copy of RuleFinding
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$RuleFindingImplCopyWith<_$RuleFindingImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

GameStats _$GameStatsFromJson(Map<String, dynamic> json) {
  return _GameStats.fromJson(json);
}

/// @nodoc
mixin _$GameStats {
  int get total_moves => throw _privateConstructorUsedError;
  int get auto_resolved => throw _privateConstructorUsedError;
  int get manual_review_required => throw _privateConstructorUsedError;
  int get illegal_moves => throw _privateConstructorUsedError;
  double get ocr_avg_confidence => throw _privateConstructorUsedError;

  /// Serializes this GameStats to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of GameStats
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $GameStatsCopyWith<GameStats> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $GameStatsCopyWith<$Res> {
  factory $GameStatsCopyWith(GameStats value, $Res Function(GameStats) then) =
      _$GameStatsCopyWithImpl<$Res, GameStats>;
  @useResult
  $Res call({
    int total_moves,
    int auto_resolved,
    int manual_review_required,
    int illegal_moves,
    double ocr_avg_confidence,
  });
}

/// @nodoc
class _$GameStatsCopyWithImpl<$Res, $Val extends GameStats>
    implements $GameStatsCopyWith<$Res> {
  _$GameStatsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of GameStats
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? total_moves = null,
    Object? auto_resolved = null,
    Object? manual_review_required = null,
    Object? illegal_moves = null,
    Object? ocr_avg_confidence = null,
  }) {
    return _then(
      _value.copyWith(
            total_moves: null == total_moves
                ? _value.total_moves
                : total_moves // ignore: cast_nullable_to_non_nullable
                      as int,
            auto_resolved: null == auto_resolved
                ? _value.auto_resolved
                : auto_resolved // ignore: cast_nullable_to_non_nullable
                      as int,
            manual_review_required: null == manual_review_required
                ? _value.manual_review_required
                : manual_review_required // ignore: cast_nullable_to_non_nullable
                      as int,
            illegal_moves: null == illegal_moves
                ? _value.illegal_moves
                : illegal_moves // ignore: cast_nullable_to_non_nullable
                      as int,
            ocr_avg_confidence: null == ocr_avg_confidence
                ? _value.ocr_avg_confidence
                : ocr_avg_confidence // ignore: cast_nullable_to_non_nullable
                      as double,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$GameStatsImplCopyWith<$Res>
    implements $GameStatsCopyWith<$Res> {
  factory _$$GameStatsImplCopyWith(
    _$GameStatsImpl value,
    $Res Function(_$GameStatsImpl) then,
  ) = __$$GameStatsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    int total_moves,
    int auto_resolved,
    int manual_review_required,
    int illegal_moves,
    double ocr_avg_confidence,
  });
}

/// @nodoc
class __$$GameStatsImplCopyWithImpl<$Res>
    extends _$GameStatsCopyWithImpl<$Res, _$GameStatsImpl>
    implements _$$GameStatsImplCopyWith<$Res> {
  __$$GameStatsImplCopyWithImpl(
    _$GameStatsImpl _value,
    $Res Function(_$GameStatsImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of GameStats
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? total_moves = null,
    Object? auto_resolved = null,
    Object? manual_review_required = null,
    Object? illegal_moves = null,
    Object? ocr_avg_confidence = null,
  }) {
    return _then(
      _$GameStatsImpl(
        total_moves: null == total_moves
            ? _value.total_moves
            : total_moves // ignore: cast_nullable_to_non_nullable
                  as int,
        auto_resolved: null == auto_resolved
            ? _value.auto_resolved
            : auto_resolved // ignore: cast_nullable_to_non_nullable
                  as int,
        manual_review_required: null == manual_review_required
            ? _value.manual_review_required
            : manual_review_required // ignore: cast_nullable_to_non_nullable
                  as int,
        illegal_moves: null == illegal_moves
            ? _value.illegal_moves
            : illegal_moves // ignore: cast_nullable_to_non_nullable
                  as int,
        ocr_avg_confidence: null == ocr_avg_confidence
            ? _value.ocr_avg_confidence
            : ocr_avg_confidence // ignore: cast_nullable_to_non_nullable
                  as double,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$GameStatsImpl implements _GameStats {
  const _$GameStatsImpl({
    required this.total_moves,
    required this.auto_resolved,
    required this.manual_review_required,
    required this.illegal_moves,
    required this.ocr_avg_confidence,
  });

  factory _$GameStatsImpl.fromJson(Map<String, dynamic> json) =>
      _$$GameStatsImplFromJson(json);

  @override
  final int total_moves;
  @override
  final int auto_resolved;
  @override
  final int manual_review_required;
  @override
  final int illegal_moves;
  @override
  final double ocr_avg_confidence;

  @override
  String toString() {
    return 'GameStats(total_moves: $total_moves, auto_resolved: $auto_resolved, manual_review_required: $manual_review_required, illegal_moves: $illegal_moves, ocr_avg_confidence: $ocr_avg_confidence)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$GameStatsImpl &&
            (identical(other.total_moves, total_moves) ||
                other.total_moves == total_moves) &&
            (identical(other.auto_resolved, auto_resolved) ||
                other.auto_resolved == auto_resolved) &&
            (identical(other.manual_review_required, manual_review_required) ||
                other.manual_review_required == manual_review_required) &&
            (identical(other.illegal_moves, illegal_moves) ||
                other.illegal_moves == illegal_moves) &&
            (identical(other.ocr_avg_confidence, ocr_avg_confidence) ||
                other.ocr_avg_confidence == ocr_avg_confidence));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    total_moves,
    auto_resolved,
    manual_review_required,
    illegal_moves,
    ocr_avg_confidence,
  );

  /// Create a copy of GameStats
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$GameStatsImplCopyWith<_$GameStatsImpl> get copyWith =>
      __$$GameStatsImplCopyWithImpl<_$GameStatsImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$GameStatsImplToJson(this);
  }
}

abstract class _GameStats implements GameStats {
  const factory _GameStats({
    required final int total_moves,
    required final int auto_resolved,
    required final int manual_review_required,
    required final int illegal_moves,
    required final double ocr_avg_confidence,
  }) = _$GameStatsImpl;

  factory _GameStats.fromJson(Map<String, dynamic> json) =
      _$GameStatsImpl.fromJson;

  @override
  int get total_moves;
  @override
  int get auto_resolved;
  @override
  int get manual_review_required;
  @override
  int get illegal_moves;
  @override
  double get ocr_avg_confidence;

  /// Create a copy of GameStats
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$GameStatsImplCopyWith<_$GameStatsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

UploadMetadata _$UploadMetadataFromJson(Map<String, dynamic> json) {
  return _UploadMetadata.fromJson(json);
}

/// @nodoc
mixin _$UploadMetadata {
  String? get filename => throw _privateConstructorUsedError;
  String? get uploaded_at => throw _privateConstructorUsedError;

  /// Serializes this UploadMetadata to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of UploadMetadata
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $UploadMetadataCopyWith<UploadMetadata> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $UploadMetadataCopyWith<$Res> {
  factory $UploadMetadataCopyWith(
    UploadMetadata value,
    $Res Function(UploadMetadata) then,
  ) = _$UploadMetadataCopyWithImpl<$Res, UploadMetadata>;
  @useResult
  $Res call({String? filename, String? uploaded_at});
}

/// @nodoc
class _$UploadMetadataCopyWithImpl<$Res, $Val extends UploadMetadata>
    implements $UploadMetadataCopyWith<$Res> {
  _$UploadMetadataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of UploadMetadata
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? filename = freezed, Object? uploaded_at = freezed}) {
    return _then(
      _value.copyWith(
            filename: freezed == filename
                ? _value.filename
                : filename // ignore: cast_nullable_to_non_nullable
                      as String?,
            uploaded_at: freezed == uploaded_at
                ? _value.uploaded_at
                : uploaded_at // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$UploadMetadataImplCopyWith<$Res>
    implements $UploadMetadataCopyWith<$Res> {
  factory _$$UploadMetadataImplCopyWith(
    _$UploadMetadataImpl value,
    $Res Function(_$UploadMetadataImpl) then,
  ) = __$$UploadMetadataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? filename, String? uploaded_at});
}

/// @nodoc
class __$$UploadMetadataImplCopyWithImpl<$Res>
    extends _$UploadMetadataCopyWithImpl<$Res, _$UploadMetadataImpl>
    implements _$$UploadMetadataImplCopyWith<$Res> {
  __$$UploadMetadataImplCopyWithImpl(
    _$UploadMetadataImpl _value,
    $Res Function(_$UploadMetadataImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of UploadMetadata
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? filename = freezed, Object? uploaded_at = freezed}) {
    return _then(
      _$UploadMetadataImpl(
        filename: freezed == filename
            ? _value.filename
            : filename // ignore: cast_nullable_to_non_nullable
                  as String?,
        uploaded_at: freezed == uploaded_at
            ? _value.uploaded_at
            : uploaded_at // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$UploadMetadataImpl implements _UploadMetadata {
  const _$UploadMetadataImpl({this.filename, this.uploaded_at});

  factory _$UploadMetadataImpl.fromJson(Map<String, dynamic> json) =>
      _$$UploadMetadataImplFromJson(json);

  @override
  final String? filename;
  @override
  final String? uploaded_at;

  @override
  String toString() {
    return 'UploadMetadata(filename: $filename, uploaded_at: $uploaded_at)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UploadMetadataImpl &&
            (identical(other.filename, filename) ||
                other.filename == filename) &&
            (identical(other.uploaded_at, uploaded_at) ||
                other.uploaded_at == uploaded_at));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, filename, uploaded_at);

  /// Create a copy of UploadMetadata
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$UploadMetadataImplCopyWith<_$UploadMetadataImpl> get copyWith =>
      __$$UploadMetadataImplCopyWithImpl<_$UploadMetadataImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$UploadMetadataImplToJson(this);
  }
}

abstract class _UploadMetadata implements UploadMetadata {
  const factory _UploadMetadata({
    final String? filename,
    final String? uploaded_at,
  }) = _$UploadMetadataImpl;

  factory _UploadMetadata.fromJson(Map<String, dynamic> json) =
      _$UploadMetadataImpl.fromJson;

  @override
  String? get filename;
  @override
  String? get uploaded_at;

  /// Create a copy of UploadMetadata
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$UploadMetadataImplCopyWith<_$UploadMetadataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

MoveAnalysis _$MoveAnalysisFromJson(Map<String, dynamic> json) {
  return _MoveAnalysis.fromJson(json);
}

/// @nodoc
mixin _$MoveAnalysis {
  int get move_number => throw _privateConstructorUsedError;
  int get ply_index => throw _privateConstructorUsedError;
  String get color => throw _privateConstructorUsedError;
  String get ocr_raw_text => throw _privateConstructorUsedError;
  List<OcrCandidate> get ocr_candidates => throw _privateConstructorUsedError;
  String get normalized_text => throw _privateConstructorUsedError;
  String? get selected_san => throw _privateConstructorUsedError;
  String? get selected_uci => throw _privateConstructorUsedError;
  String get fen_before => throw _privateConstructorUsedError;
  String get fen_after => throw _privateConstructorUsedError;
  bool get is_legal => throw _privateConstructorUsedError;
  bool get needs_manual_review => throw _privateConstructorUsedError;
  double get confidence => throw _privateConstructorUsedError;
  List<String> get review_reasons => throw _privateConstructorUsedError;
  List<String> get fide_alerts => throw _privateConstructorUsedError;
  String? get crop_image_url => throw _privateConstructorUsedError;
  String? get check_square => throw _privateConstructorUsedError;

  /// Serializes this MoveAnalysis to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of MoveAnalysis
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MoveAnalysisCopyWith<MoveAnalysis> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MoveAnalysisCopyWith<$Res> {
  factory $MoveAnalysisCopyWith(
    MoveAnalysis value,
    $Res Function(MoveAnalysis) then,
  ) = _$MoveAnalysisCopyWithImpl<$Res, MoveAnalysis>;
  @useResult
  $Res call({
    int move_number,
    int ply_index,
    String color,
    String ocr_raw_text,
    List<OcrCandidate> ocr_candidates,
    String normalized_text,
    String? selected_san,
    String? selected_uci,
    String fen_before,
    String fen_after,
    bool is_legal,
    bool needs_manual_review,
    double confidence,
    List<String> review_reasons,
    List<String> fide_alerts,
    String? crop_image_url,
    String? check_square,
  });
}

/// @nodoc
class _$MoveAnalysisCopyWithImpl<$Res, $Val extends MoveAnalysis>
    implements $MoveAnalysisCopyWith<$Res> {
  _$MoveAnalysisCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of MoveAnalysis
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? move_number = null,
    Object? ply_index = null,
    Object? color = null,
    Object? ocr_raw_text = null,
    Object? ocr_candidates = null,
    Object? normalized_text = null,
    Object? selected_san = freezed,
    Object? selected_uci = freezed,
    Object? fen_before = null,
    Object? fen_after = null,
    Object? is_legal = null,
    Object? needs_manual_review = null,
    Object? confidence = null,
    Object? review_reasons = null,
    Object? fide_alerts = null,
    Object? crop_image_url = freezed,
    Object? check_square = freezed,
  }) {
    return _then(
      _value.copyWith(
            move_number: null == move_number
                ? _value.move_number
                : move_number // ignore: cast_nullable_to_non_nullable
                      as int,
            ply_index: null == ply_index
                ? _value.ply_index
                : ply_index // ignore: cast_nullable_to_non_nullable
                      as int,
            color: null == color
                ? _value.color
                : color // ignore: cast_nullable_to_non_nullable
                      as String,
            ocr_raw_text: null == ocr_raw_text
                ? _value.ocr_raw_text
                : ocr_raw_text // ignore: cast_nullable_to_non_nullable
                      as String,
            ocr_candidates: null == ocr_candidates
                ? _value.ocr_candidates
                : ocr_candidates // ignore: cast_nullable_to_non_nullable
                      as List<OcrCandidate>,
            normalized_text: null == normalized_text
                ? _value.normalized_text
                : normalized_text // ignore: cast_nullable_to_non_nullable
                      as String,
            selected_san: freezed == selected_san
                ? _value.selected_san
                : selected_san // ignore: cast_nullable_to_non_nullable
                      as String?,
            selected_uci: freezed == selected_uci
                ? _value.selected_uci
                : selected_uci // ignore: cast_nullable_to_non_nullable
                      as String?,
            fen_before: null == fen_before
                ? _value.fen_before
                : fen_before // ignore: cast_nullable_to_non_nullable
                      as String,
            fen_after: null == fen_after
                ? _value.fen_after
                : fen_after // ignore: cast_nullable_to_non_nullable
                      as String,
            is_legal: null == is_legal
                ? _value.is_legal
                : is_legal // ignore: cast_nullable_to_non_nullable
                      as bool,
            needs_manual_review: null == needs_manual_review
                ? _value.needs_manual_review
                : needs_manual_review // ignore: cast_nullable_to_non_nullable
                      as bool,
            confidence: null == confidence
                ? _value.confidence
                : confidence // ignore: cast_nullable_to_non_nullable
                      as double,
            review_reasons: null == review_reasons
                ? _value.review_reasons
                : review_reasons // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            fide_alerts: null == fide_alerts
                ? _value.fide_alerts
                : fide_alerts // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            crop_image_url: freezed == crop_image_url
                ? _value.crop_image_url
                : crop_image_url // ignore: cast_nullable_to_non_nullable
                      as String?,
            check_square: freezed == check_square
                ? _value.check_square
                : check_square // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$MoveAnalysisImplCopyWith<$Res>
    implements $MoveAnalysisCopyWith<$Res> {
  factory _$$MoveAnalysisImplCopyWith(
    _$MoveAnalysisImpl value,
    $Res Function(_$MoveAnalysisImpl) then,
  ) = __$$MoveAnalysisImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    int move_number,
    int ply_index,
    String color,
    String ocr_raw_text,
    List<OcrCandidate> ocr_candidates,
    String normalized_text,
    String? selected_san,
    String? selected_uci,
    String fen_before,
    String fen_after,
    bool is_legal,
    bool needs_manual_review,
    double confidence,
    List<String> review_reasons,
    List<String> fide_alerts,
    String? crop_image_url,
    String? check_square,
  });
}

/// @nodoc
class __$$MoveAnalysisImplCopyWithImpl<$Res>
    extends _$MoveAnalysisCopyWithImpl<$Res, _$MoveAnalysisImpl>
    implements _$$MoveAnalysisImplCopyWith<$Res> {
  __$$MoveAnalysisImplCopyWithImpl(
    _$MoveAnalysisImpl _value,
    $Res Function(_$MoveAnalysisImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of MoveAnalysis
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? move_number = null,
    Object? ply_index = null,
    Object? color = null,
    Object? ocr_raw_text = null,
    Object? ocr_candidates = null,
    Object? normalized_text = null,
    Object? selected_san = freezed,
    Object? selected_uci = freezed,
    Object? fen_before = null,
    Object? fen_after = null,
    Object? is_legal = null,
    Object? needs_manual_review = null,
    Object? confidence = null,
    Object? review_reasons = null,
    Object? fide_alerts = null,
    Object? crop_image_url = freezed,
    Object? check_square = freezed,
  }) {
    return _then(
      _$MoveAnalysisImpl(
        move_number: null == move_number
            ? _value.move_number
            : move_number // ignore: cast_nullable_to_non_nullable
                  as int,
        ply_index: null == ply_index
            ? _value.ply_index
            : ply_index // ignore: cast_nullable_to_non_nullable
                  as int,
        color: null == color
            ? _value.color
            : color // ignore: cast_nullable_to_non_nullable
                  as String,
        ocr_raw_text: null == ocr_raw_text
            ? _value.ocr_raw_text
            : ocr_raw_text // ignore: cast_nullable_to_non_nullable
                  as String,
        ocr_candidates: null == ocr_candidates
            ? _value._ocr_candidates
            : ocr_candidates // ignore: cast_nullable_to_non_nullable
                  as List<OcrCandidate>,
        normalized_text: null == normalized_text
            ? _value.normalized_text
            : normalized_text // ignore: cast_nullable_to_non_nullable
                  as String,
        selected_san: freezed == selected_san
            ? _value.selected_san
            : selected_san // ignore: cast_nullable_to_non_nullable
                  as String?,
        selected_uci: freezed == selected_uci
            ? _value.selected_uci
            : selected_uci // ignore: cast_nullable_to_non_nullable
                  as String?,
        fen_before: null == fen_before
            ? _value.fen_before
            : fen_before // ignore: cast_nullable_to_non_nullable
                  as String,
        fen_after: null == fen_after
            ? _value.fen_after
            : fen_after // ignore: cast_nullable_to_non_nullable
                  as String,
        is_legal: null == is_legal
            ? _value.is_legal
            : is_legal // ignore: cast_nullable_to_non_nullable
                  as bool,
        needs_manual_review: null == needs_manual_review
            ? _value.needs_manual_review
            : needs_manual_review // ignore: cast_nullable_to_non_nullable
                  as bool,
        confidence: null == confidence
            ? _value.confidence
            : confidence // ignore: cast_nullable_to_non_nullable
                  as double,
        review_reasons: null == review_reasons
            ? _value._review_reasons
            : review_reasons // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        fide_alerts: null == fide_alerts
            ? _value._fide_alerts
            : fide_alerts // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        crop_image_url: freezed == crop_image_url
            ? _value.crop_image_url
            : crop_image_url // ignore: cast_nullable_to_non_nullable
                  as String?,
        check_square: freezed == check_square
            ? _value.check_square
            : check_square // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$MoveAnalysisImpl implements _MoveAnalysis {
  const _$MoveAnalysisImpl({
    required this.move_number,
    required this.ply_index,
    required this.color,
    required this.ocr_raw_text,
    required final List<OcrCandidate> ocr_candidates,
    required this.normalized_text,
    this.selected_san,
    this.selected_uci,
    required this.fen_before,
    required this.fen_after,
    required this.is_legal,
    required this.needs_manual_review,
    required this.confidence,
    final List<String> review_reasons = const [],
    final List<String> fide_alerts = const [],
    this.crop_image_url,
    this.check_square,
  }) : _ocr_candidates = ocr_candidates,
       _review_reasons = review_reasons,
       _fide_alerts = fide_alerts;

  factory _$MoveAnalysisImpl.fromJson(Map<String, dynamic> json) =>
      _$$MoveAnalysisImplFromJson(json);

  @override
  final int move_number;
  @override
  final int ply_index;
  @override
  final String color;
  @override
  final String ocr_raw_text;
  final List<OcrCandidate> _ocr_candidates;
  @override
  List<OcrCandidate> get ocr_candidates {
    if (_ocr_candidates is EqualUnmodifiableListView) return _ocr_candidates;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_ocr_candidates);
  }

  @override
  final String normalized_text;
  @override
  final String? selected_san;
  @override
  final String? selected_uci;
  @override
  final String fen_before;
  @override
  final String fen_after;
  @override
  final bool is_legal;
  @override
  final bool needs_manual_review;
  @override
  final double confidence;
  final List<String> _review_reasons;
  @override
  @JsonKey()
  List<String> get review_reasons {
    if (_review_reasons is EqualUnmodifiableListView) return _review_reasons;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_review_reasons);
  }

  final List<String> _fide_alerts;
  @override
  @JsonKey()
  List<String> get fide_alerts {
    if (_fide_alerts is EqualUnmodifiableListView) return _fide_alerts;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_fide_alerts);
  }

  @override
  final String? crop_image_url;
  @override
  final String? check_square;

  @override
  String toString() {
    return 'MoveAnalysis(move_number: $move_number, ply_index: $ply_index, color: $color, ocr_raw_text: $ocr_raw_text, ocr_candidates: $ocr_candidates, normalized_text: $normalized_text, selected_san: $selected_san, selected_uci: $selected_uci, fen_before: $fen_before, fen_after: $fen_after, is_legal: $is_legal, needs_manual_review: $needs_manual_review, confidence: $confidence, review_reasons: $review_reasons, fide_alerts: $fide_alerts, crop_image_url: $crop_image_url, check_square: $check_square)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MoveAnalysisImpl &&
            (identical(other.move_number, move_number) ||
                other.move_number == move_number) &&
            (identical(other.ply_index, ply_index) ||
                other.ply_index == ply_index) &&
            (identical(other.color, color) || other.color == color) &&
            (identical(other.ocr_raw_text, ocr_raw_text) ||
                other.ocr_raw_text == ocr_raw_text) &&
            const DeepCollectionEquality().equals(
              other._ocr_candidates,
              _ocr_candidates,
            ) &&
            (identical(other.normalized_text, normalized_text) ||
                other.normalized_text == normalized_text) &&
            (identical(other.selected_san, selected_san) ||
                other.selected_san == selected_san) &&
            (identical(other.selected_uci, selected_uci) ||
                other.selected_uci == selected_uci) &&
            (identical(other.fen_before, fen_before) ||
                other.fen_before == fen_before) &&
            (identical(other.fen_after, fen_after) ||
                other.fen_after == fen_after) &&
            (identical(other.is_legal, is_legal) ||
                other.is_legal == is_legal) &&
            (identical(other.needs_manual_review, needs_manual_review) ||
                other.needs_manual_review == needs_manual_review) &&
            (identical(other.confidence, confidence) ||
                other.confidence == confidence) &&
            const DeepCollectionEquality().equals(
              other._review_reasons,
              _review_reasons,
            ) &&
            const DeepCollectionEquality().equals(
              other._fide_alerts,
              _fide_alerts,
            ) &&
            (identical(other.crop_image_url, crop_image_url) ||
                other.crop_image_url == crop_image_url) &&
            (identical(other.check_square, check_square) ||
                other.check_square == check_square));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    move_number,
    ply_index,
    color,
    ocr_raw_text,
    const DeepCollectionEquality().hash(_ocr_candidates),
    normalized_text,
    selected_san,
    selected_uci,
    fen_before,
    fen_after,
    is_legal,
    needs_manual_review,
    confidence,
    const DeepCollectionEquality().hash(_review_reasons),
    const DeepCollectionEquality().hash(_fide_alerts),
    crop_image_url,
    check_square,
  );

  /// Create a copy of MoveAnalysis
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MoveAnalysisImplCopyWith<_$MoveAnalysisImpl> get copyWith =>
      __$$MoveAnalysisImplCopyWithImpl<_$MoveAnalysisImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$MoveAnalysisImplToJson(this);
  }
}

abstract class _MoveAnalysis implements MoveAnalysis {
  const factory _MoveAnalysis({
    required final int move_number,
    required final int ply_index,
    required final String color,
    required final String ocr_raw_text,
    required final List<OcrCandidate> ocr_candidates,
    required final String normalized_text,
    final String? selected_san,
    final String? selected_uci,
    required final String fen_before,
    required final String fen_after,
    required final bool is_legal,
    required final bool needs_manual_review,
    required final double confidence,
    final List<String> review_reasons,
    final List<String> fide_alerts,
    final String? crop_image_url,
    final String? check_square,
  }) = _$MoveAnalysisImpl;

  factory _MoveAnalysis.fromJson(Map<String, dynamic> json) =
      _$MoveAnalysisImpl.fromJson;

  @override
  int get move_number;
  @override
  int get ply_index;
  @override
  String get color;
  @override
  String get ocr_raw_text;
  @override
  List<OcrCandidate> get ocr_candidates;
  @override
  String get normalized_text;
  @override
  String? get selected_san;
  @override
  String? get selected_uci;
  @override
  String get fen_before;
  @override
  String get fen_after;
  @override
  bool get is_legal;
  @override
  bool get needs_manual_review;
  @override
  double get confidence;
  @override
  List<String> get review_reasons;
  @override
  List<String> get fide_alerts;
  @override
  String? get crop_image_url;
  @override
  String? get check_square;

  /// Create a copy of MoveAnalysis
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MoveAnalysisImplCopyWith<_$MoveAnalysisImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

GameAnalysisResponse _$GameAnalysisResponseFromJson(Map<String, dynamic> json) {
  return _GameAnalysisResponse.fromJson(json);
}

/// @nodoc
mixin _$GameAnalysisResponse {
  String get game_id => throw _privateConstructorUsedError;
  String get session_id => throw _privateConstructorUsedError;
  String get status => throw _privateConstructorUsedError;
  UploadMetadata get upload_metadata => throw _privateConstructorUsedError;
  List<MoveAnalysis> get moves => throw _privateConstructorUsedError;
  List<RuleFinding> get findings => throw _privateConstructorUsedError;
  String get pgn => throw _privateConstructorUsedError;
  int? get failure_point_ply => throw _privateConstructorUsedError;
  GameStats get stats => throw _privateConstructorUsedError;
  String get draw_decision => throw _privateConstructorUsedError;
  String? get draw_reason => throw _privateConstructorUsedError;
  bool get arbiter_must_end => throw _privateConstructorUsedError;
  bool get requires_player_claim => throw _privateConstructorUsedError;

  /// Serializes this GameAnalysisResponse to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of GameAnalysisResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $GameAnalysisResponseCopyWith<GameAnalysisResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $GameAnalysisResponseCopyWith<$Res> {
  factory $GameAnalysisResponseCopyWith(
    GameAnalysisResponse value,
    $Res Function(GameAnalysisResponse) then,
  ) = _$GameAnalysisResponseCopyWithImpl<$Res, GameAnalysisResponse>;
  @useResult
  $Res call({
    String game_id,
    String session_id,
    String status,
    UploadMetadata upload_metadata,
    List<MoveAnalysis> moves,
    List<RuleFinding> findings,
    String pgn,
    int? failure_point_ply,
    GameStats stats,
    String draw_decision,
    String? draw_reason,
    bool arbiter_must_end,
    bool requires_player_claim,
  });

  $UploadMetadataCopyWith<$Res> get upload_metadata;
  $GameStatsCopyWith<$Res> get stats;
}

/// @nodoc
class _$GameAnalysisResponseCopyWithImpl<
  $Res,
  $Val extends GameAnalysisResponse
>
    implements $GameAnalysisResponseCopyWith<$Res> {
  _$GameAnalysisResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of GameAnalysisResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? game_id = null,
    Object? session_id = null,
    Object? status = null,
    Object? upload_metadata = null,
    Object? moves = null,
    Object? findings = null,
    Object? pgn = null,
    Object? failure_point_ply = freezed,
    Object? stats = null,
    Object? draw_decision = null,
    Object? draw_reason = freezed,
    Object? arbiter_must_end = null,
    Object? requires_player_claim = null,
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
            upload_metadata: null == upload_metadata
                ? _value.upload_metadata
                : upload_metadata // ignore: cast_nullable_to_non_nullable
                      as UploadMetadata,
            moves: null == moves
                ? _value.moves
                : moves // ignore: cast_nullable_to_non_nullable
                      as List<MoveAnalysis>,
            findings: null == findings
                ? _value.findings
                : findings // ignore: cast_nullable_to_non_nullable
                      as List<RuleFinding>,
            pgn: null == pgn
                ? _value.pgn
                : pgn // ignore: cast_nullable_to_non_nullable
                      as String,
            failure_point_ply: freezed == failure_point_ply
                ? _value.failure_point_ply
                : failure_point_ply // ignore: cast_nullable_to_non_nullable
                      as int?,
            stats: null == stats
                ? _value.stats
                : stats // ignore: cast_nullable_to_non_nullable
                      as GameStats,
            draw_decision: null == draw_decision
                ? _value.draw_decision
                : draw_decision // ignore: cast_nullable_to_non_nullable
                      as String,
            draw_reason: freezed == draw_reason
                ? _value.draw_reason
                : draw_reason // ignore: cast_nullable_to_non_nullable
                      as String?,
            arbiter_must_end: null == arbiter_must_end
                ? _value.arbiter_must_end
                : arbiter_must_end // ignore: cast_nullable_to_non_nullable
                      as bool,
            requires_player_claim: null == requires_player_claim
                ? _value.requires_player_claim
                : requires_player_claim // ignore: cast_nullable_to_non_nullable
                      as bool,
          )
          as $Val,
    );
  }

  /// Create a copy of GameAnalysisResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $UploadMetadataCopyWith<$Res> get upload_metadata {
    return $UploadMetadataCopyWith<$Res>(_value.upload_metadata, (value) {
      return _then(_value.copyWith(upload_metadata: value) as $Val);
    });
  }

  /// Create a copy of GameAnalysisResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $GameStatsCopyWith<$Res> get stats {
    return $GameStatsCopyWith<$Res>(_value.stats, (value) {
      return _then(_value.copyWith(stats: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$GameAnalysisResponseImplCopyWith<$Res>
    implements $GameAnalysisResponseCopyWith<$Res> {
  factory _$$GameAnalysisResponseImplCopyWith(
    _$GameAnalysisResponseImpl value,
    $Res Function(_$GameAnalysisResponseImpl) then,
  ) = __$$GameAnalysisResponseImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String game_id,
    String session_id,
    String status,
    UploadMetadata upload_metadata,
    List<MoveAnalysis> moves,
    List<RuleFinding> findings,
    String pgn,
    int? failure_point_ply,
    GameStats stats,
    String draw_decision,
    String? draw_reason,
    bool arbiter_must_end,
    bool requires_player_claim,
  });

  @override
  $UploadMetadataCopyWith<$Res> get upload_metadata;
  @override
  $GameStatsCopyWith<$Res> get stats;
}

/// @nodoc
class __$$GameAnalysisResponseImplCopyWithImpl<$Res>
    extends _$GameAnalysisResponseCopyWithImpl<$Res, _$GameAnalysisResponseImpl>
    implements _$$GameAnalysisResponseImplCopyWith<$Res> {
  __$$GameAnalysisResponseImplCopyWithImpl(
    _$GameAnalysisResponseImpl _value,
    $Res Function(_$GameAnalysisResponseImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of GameAnalysisResponse
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? game_id = null,
    Object? session_id = null,
    Object? status = null,
    Object? upload_metadata = null,
    Object? moves = null,
    Object? findings = null,
    Object? pgn = null,
    Object? failure_point_ply = freezed,
    Object? stats = null,
    Object? draw_decision = null,
    Object? draw_reason = freezed,
    Object? arbiter_must_end = null,
    Object? requires_player_claim = null,
  }) {
    return _then(
      _$GameAnalysisResponseImpl(
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
        upload_metadata: null == upload_metadata
            ? _value.upload_metadata
            : upload_metadata // ignore: cast_nullable_to_non_nullable
                  as UploadMetadata,
        moves: null == moves
            ? _value._moves
            : moves // ignore: cast_nullable_to_non_nullable
                  as List<MoveAnalysis>,
        findings: null == findings
            ? _value._findings
            : findings // ignore: cast_nullable_to_non_nullable
                  as List<RuleFinding>,
        pgn: null == pgn
            ? _value.pgn
            : pgn // ignore: cast_nullable_to_non_nullable
                  as String,
        failure_point_ply: freezed == failure_point_ply
            ? _value.failure_point_ply
            : failure_point_ply // ignore: cast_nullable_to_non_nullable
                  as int?,
        stats: null == stats
            ? _value.stats
            : stats // ignore: cast_nullable_to_non_nullable
                  as GameStats,
        draw_decision: null == draw_decision
            ? _value.draw_decision
            : draw_decision // ignore: cast_nullable_to_non_nullable
                  as String,
        draw_reason: freezed == draw_reason
            ? _value.draw_reason
            : draw_reason // ignore: cast_nullable_to_non_nullable
                  as String?,
        arbiter_must_end: null == arbiter_must_end
            ? _value.arbiter_must_end
            : arbiter_must_end // ignore: cast_nullable_to_non_nullable
                  as bool,
        requires_player_claim: null == requires_player_claim
            ? _value.requires_player_claim
            : requires_player_claim // ignore: cast_nullable_to_non_nullable
                  as bool,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$GameAnalysisResponseImpl implements _GameAnalysisResponse {
  const _$GameAnalysisResponseImpl({
    required this.game_id,
    required this.session_id,
    required this.status,
    required this.upload_metadata,
    required final List<MoveAnalysis> moves,
    required final List<RuleFinding> findings,
    required this.pgn,
    this.failure_point_ply,
    required this.stats,
    this.draw_decision = 'none',
    this.draw_reason,
    this.arbiter_must_end = false,
    this.requires_player_claim = false,
  }) : _moves = moves,
       _findings = findings;

  factory _$GameAnalysisResponseImpl.fromJson(Map<String, dynamic> json) =>
      _$$GameAnalysisResponseImplFromJson(json);

  @override
  final String game_id;
  @override
  final String session_id;
  @override
  final String status;
  @override
  final UploadMetadata upload_metadata;
  final List<MoveAnalysis> _moves;
  @override
  List<MoveAnalysis> get moves {
    if (_moves is EqualUnmodifiableListView) return _moves;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_moves);
  }

  final List<RuleFinding> _findings;
  @override
  List<RuleFinding> get findings {
    if (_findings is EqualUnmodifiableListView) return _findings;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_findings);
  }

  @override
  final String pgn;
  @override
  final int? failure_point_ply;
  @override
  final GameStats stats;
  @override
  @JsonKey()
  final String draw_decision;
  @override
  final String? draw_reason;
  @override
  @JsonKey()
  final bool arbiter_must_end;
  @override
  @JsonKey()
  final bool requires_player_claim;

  @override
  String toString() {
    return 'GameAnalysisResponse(game_id: $game_id, session_id: $session_id, status: $status, upload_metadata: $upload_metadata, moves: $moves, findings: $findings, pgn: $pgn, failure_point_ply: $failure_point_ply, stats: $stats, draw_decision: $draw_decision, draw_reason: $draw_reason, arbiter_must_end: $arbiter_must_end, requires_player_claim: $requires_player_claim)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$GameAnalysisResponseImpl &&
            (identical(other.game_id, game_id) || other.game_id == game_id) &&
            (identical(other.session_id, session_id) ||
                other.session_id == session_id) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.upload_metadata, upload_metadata) ||
                other.upload_metadata == upload_metadata) &&
            const DeepCollectionEquality().equals(other._moves, _moves) &&
            const DeepCollectionEquality().equals(other._findings, _findings) &&
            (identical(other.pgn, pgn) || other.pgn == pgn) &&
            (identical(other.failure_point_ply, failure_point_ply) ||
                other.failure_point_ply == failure_point_ply) &&
            (identical(other.stats, stats) || other.stats == stats) &&
            (identical(other.draw_decision, draw_decision) ||
                other.draw_decision == draw_decision) &&
            (identical(other.draw_reason, draw_reason) ||
                other.draw_reason == draw_reason) &&
            (identical(other.arbiter_must_end, arbiter_must_end) ||
                other.arbiter_must_end == arbiter_must_end) &&
            (identical(other.requires_player_claim, requires_player_claim) ||
                other.requires_player_claim == requires_player_claim));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    game_id,
    session_id,
    status,
    upload_metadata,
    const DeepCollectionEquality().hash(_moves),
    const DeepCollectionEquality().hash(_findings),
    pgn,
    failure_point_ply,
    stats,
    draw_decision,
    draw_reason,
    arbiter_must_end,
    requires_player_claim,
  );

  /// Create a copy of GameAnalysisResponse
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$GameAnalysisResponseImplCopyWith<_$GameAnalysisResponseImpl>
  get copyWith =>
      __$$GameAnalysisResponseImplCopyWithImpl<_$GameAnalysisResponseImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$GameAnalysisResponseImplToJson(this);
  }
}

abstract class _GameAnalysisResponse implements GameAnalysisResponse {
  const factory _GameAnalysisResponse({
    required final String game_id,
    required final String session_id,
    required final String status,
    required final UploadMetadata upload_metadata,
    required final List<MoveAnalysis> moves,
    required final List<RuleFinding> findings,
    required final String pgn,
    final int? failure_point_ply,
    required final GameStats stats,
    final String draw_decision,
    final String? draw_reason,
    final bool arbiter_must_end,
    final bool requires_player_claim,
  }) = _$GameAnalysisResponseImpl;

  factory _GameAnalysisResponse.fromJson(Map<String, dynamic> json) =
      _$GameAnalysisResponseImpl.fromJson;

  @override
  String get game_id;
  @override
  String get session_id;
  @override
  String get status;
  @override
  UploadMetadata get upload_metadata;
  @override
  List<MoveAnalysis> get moves;
  @override
  List<RuleFinding> get findings;
  @override
  String get pgn;
  @override
  int? get failure_point_ply;
  @override
  GameStats get stats;
  @override
  String get draw_decision;
  @override
  String? get draw_reason;
  @override
  bool get arbiter_must_end;
  @override
  bool get requires_player_claim;

  /// Create a copy of GameAnalysisResponse
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$GameAnalysisResponseImplCopyWith<_$GameAnalysisResponseImpl>
  get copyWith => throw _privateConstructorUsedError;
}
