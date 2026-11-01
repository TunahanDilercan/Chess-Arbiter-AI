import 'dart:convert' show base64Encode, utf8;
import 'dart:math' show Random;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/arbiter/analysis.dart';
import '../core/arbiter/game_record.dart';
import '../core/arbiter/time_control.dart';
import '../core/chess/notation.dart';
import '../data/game_repository.dart';
import '../models/models.dart';
import '../monetization/plans.dart';
import '../monetization/quota.dart';
import '../monetization/subscription.dart';
import '../services/api_service.dart';
import '../services/crop_service.dart';
import '../services/sse_service.dart';
import '../theme/arbiter_tokens.dart';

// ── Core singletons (overridden in main) ──────────────────────────────────────

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

final gameRepositoryProvider = Provider<GameRepository>(
  (_) => throw UnimplementedError('gameRepositoryProvider must be overridden'),
);

final subscriptionServiceProvider = Provider<SubscriptionService>(
  (_) => throw UnimplementedError('subscriptionServiceProvider must be overridden'),
);

// ── Games (on-device) ─────────────────────────────────────────────────────────

class GamesNotifier extends AsyncNotifier<List<GameRecord>> {
  @override
  Future<List<GameRecord>> build() async {
    final list = await ref.read(gameRepositoryProvider).list();
    return _sorted(list);
  }

  List<GameRecord> _sorted(List<GameRecord> l) =>
      [...l]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Future<void> save(GameRecord record) async {
    await ref.read(gameRepositoryProvider).save(record);
    final current = state.valueOrNull ?? const <GameRecord>[];
    state = AsyncData(_sorted([
      for (final r in current)
        if (r.id != record.id) r,
      record,
    ]));
  }

  Future<void> delete(String id) async {
    await ref.read(gameRepositoryProvider).delete(id);
    state = AsyncData([
      for (final r in state.valueOrNull ?? const <GameRecord>[])
        if (r.id != id) r,
    ]);
  }

  /// Creates and stores a new record with the user's default settings.
  Future<GameRecord> create({
    required List<String> tokens,
    required GameSource source,
    Map<String, String> headers = const {},
    NotationLocale? locale,
    TimeControl? timeControl,
  }) async {
    final s = ref.read(settingsProvider);
    final now = DateTime.now();
    final rec = GameRecord(
      id: newRecordId(),
      createdAt: now,
      updatedAt: now,
      headers: {
        if (s.defaultEvent.isNotEmpty) 'Event': s.defaultEvent,
        ...headers,
      },
      tokens: tokens,
      locale: locale ?? s.locale,
      timeControl: timeControl ?? s.timeControl,
      source: source,
    );
    await save(rec);
    return rec;
  }
}

final gamesProvider =
    AsyncNotifierProvider<GamesNotifier, List<GameRecord>>(GamesNotifier.new);

final gameRecordProvider = Provider.family<GameRecord?, String>((ref, id) {
  final games = ref.watch(gamesProvider).valueOrNull ?? const <GameRecord>[];
  for (final g in games) {
    if (g.id == id) return g;
  }
  return null;
});

/// Analysis is recomputed only when the moves, locale or start change.
final analysisProvider = Provider.family<GameAnalysis?, String>((ref, id) {
  final rec = ref.watch(gameRecordProvider(id).select(
      (r) => r == null ? null : (r.tokens.join('\u0000'), r.locale)));
  if (rec == null) return null;
  final record = ref.read(gameRecordProvider(id))!;
  return analyzeGame(record.tokens, locale: record.locale);
});

// ── Subscription & quota ──────────────────────────────────────────────────────

final entitlementProvider = StreamProvider<Entitlement>((ref) async* {
  final svc = ref.watch(subscriptionServiceProvider);
  yield svc.current;
  yield* svc.changes;
});

bool isPro(WidgetRef ref) =>
    ref.watch(entitlementProvider).valueOrNull?.isPro ?? false;

final quotaProvider =
    Provider<UsageQuota>((ref) => UsageQuota(ref.watch(sharedPreferencesProvider)));

/// Bumped after quota consumption so widgets showing the counter rebuild.
final quotaTickProvider = StateProvider<int>((_) => 0);

// ── Settings (persisted) ──────────────────────────────────────────────────────

const _kThemeModeKey = 'theme_mode';
const _kBoardPaletteKey = 'board_palette';
const _kLocaleKey = 'notation_locale';
const _kTimeControlKey = 'time_control';
const _kArbiterKey = 'arbiter_name';
const _kEventKey = 'default_event';
const _kLocalizedKey = 'show_localized';
const _kOnboardedKey = 'onboarded_v1';

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.palette = BoardPalette.wood,
    this.locale = NotationLocale.tr,
    this.timeControl = TimeControl.standard,
    this.arbiterName = '',
    this.defaultEvent = '',
    this.showLocalized = true,
    this.onboarded = false,
  });

  final ThemeMode themeMode;
  final BoardPalette palette;

  /// Default scoresheet notation for new games.
  final NotationLocale locale;
  final TimeControl timeControl;
  final String arbiterName;

  /// Pre-filled tournament name for new games.
  final String defaultEvent;

  /// Show moves in the game's notation letters (e.g. Turkish A/F/K/V/Ş).
  final bool showLocalized;
  final bool onboarded;

  AppSettings copyWith({
    ThemeMode? themeMode,
    BoardPalette? palette,
    NotationLocale? locale,
    TimeControl? timeControl,
    String? arbiterName,
    String? defaultEvent,
    bool? showLocalized,
    bool? onboarded,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        palette: palette ?? this.palette,
        locale: locale ?? this.locale,
        timeControl: timeControl ?? this.timeControl,
        arbiterName: arbiterName ?? this.arbiterName,
        defaultEvent: defaultEvent ?? this.defaultEvent,
        showLocalized: showLocalized ?? this.showLocalized,
        onboarded: onboarded ?? this.onboarded,
      );
}

class SettingsNotifier extends Notifier<AppSettings> {
  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() {
    final p = _prefs;
    return AppSettings(
      themeMode: _parseEnum(p.getString(_kThemeModeKey), ThemeMode.values,
          ThemeMode.system),
      palette: _parseEnum(p.getString(_kBoardPaletteKey), BoardPalette.values,
          BoardPalette.wood),
      locale: _parseEnum(p.getString(_kLocaleKey), NotationLocale.values,
          NotationLocale.tr),
      timeControl: TimeControl.parse(p.getString(_kTimeControlKey)),
      arbiterName: p.getString(_kArbiterKey) ?? '',
      defaultEvent: p.getString(_kEventKey) ?? '',
      showLocalized: p.getBool(_kLocalizedKey) ?? true,
      onboarded: p.getBool(_kOnboardedKey) ?? false,
    );
  }

  void setThemeMode(ThemeMode v) {
    state = state.copyWith(themeMode: v);
    _prefs.setString(_kThemeModeKey, v.name);
  }

  void setPalette(BoardPalette v) {
    state = state.copyWith(palette: v);
    _prefs.setString(_kBoardPaletteKey, v.name);
  }

  void setLocale(NotationLocale v) {
    state = state.copyWith(locale: v);
    _prefs.setString(_kLocaleKey, v.name);
  }

  void setTimeControl(TimeControl v) {
    state = state.copyWith(timeControl: v);
    _prefs.setString(_kTimeControlKey, v.name);
  }

  void setArbiterName(String v) {
    state = state.copyWith(arbiterName: v);
    _prefs.setString(_kArbiterKey, v);
  }

  void setDefaultEvent(String v) {
    state = state.copyWith(defaultEvent: v);
    _prefs.setString(_kEventKey, v);
  }

  void setShowLocalized(bool v) {
    state = state.copyWith(showLocalized: v);
    _prefs.setBool(_kLocalizedKey, v);
  }

  void setOnboarded() {
    state = state.copyWith(onboarded: true);
    _prefs.setBool(_kOnboardedKey, true);
  }

  static T _parseEnum<T extends Enum>(String? name, List<T> values, T fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

// ── Optional cloud OCR (the only feature that needs a server) ─────────────────

/// OCR backend. Empty → photo reading is hidden; everything else works offline.
/// Build: `--dart-define=BACKEND_URL=https://ocr.example.com`
const kBackendUrl = String.fromEnvironment('BACKEND_URL');
bool get ocrConfigured => kBackendUrl.isNotEmpty;

const _kArbiterAuth = String.fromEnvironment('ARBITER_AUTH');

Map<String, String> _remoteHeaders() => {
      if (kBackendUrl.contains('ngrok')) 'ngrok-skip-browser-warning': 'true',
      if (_kArbiterAuth.contains(':'))
        'Authorization': 'Basic ${base64Encode(utf8.encode(_kArbiterAuth))}',
    };

final _regularDioProvider = Provider<Dio>((ref) => Dio(BaseOptions(
      baseUrl: kBackendUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: _remoteHeaders(),
    )));

final _streamDioProvider = Provider<Dio>((ref) => Dio(BaseOptions(
      baseUrl: kBackendUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 11),
      headers: _remoteHeaders(),
    )));

final apiServiceProvider =
    Provider<ApiService>((ref) => ApiService(ref.watch(_regularDioProvider)));

final sseServiceProvider =
    Provider<SseService>((ref) => SseService(ref.watch(_streamDioProvider)));

final imagePickerProvider = Provider<ImagePicker>((_) => ImagePicker());

/// Anonymous owner token for the OCR service.
final sessionIdProvider = FutureProvider<String>((ref) async {
  final prefs = ref.read(sharedPreferencesProvider);
  final existing = prefs.getString('session_id');
  if (existing != null && existing.isNotEmpty) return existing;
  final rng = Random.secure();
  final id = List.generate(16, (_) => rng.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  if (!await prefs.setString('session_id', id)) {
    throw StateError('Anonim oturum kaydedilemedi. Tekrar deneyin.');
  }
  return id;
});

final jobStatusProvider =
    StreamProvider.autoDispose.family<JobStatusEvent, String>((ref, jobId) {
  final cancelToken = CancelToken();
  ref.onDispose(cancelToken.cancel);
  return ref.watch(sseServiceProvider).watchJob(jobId, cancelToken: cancelToken);
});

class UploadNotifier extends AutoDisposeAsyncNotifier<UploadResponse?> {
  @override
  Future<UploadResponse?> build() async => null;

  Future<void> upload(XFile file, {String locale = 'en'}) async {
    state = const AsyncLoading();
    final api = ref.read(apiServiceProvider);
    state = await AsyncValue.guard(() async => api.uploadScoresheet(
          file: file,
          locale: locale,
          sessionId: await ref.read(sessionIdProvider.future),
        ));
  }
}

final uploadProvider =
    AsyncNotifierProvider.autoDispose<UploadNotifier, UploadResponse?>(
        UploadNotifier.new);

/// Fetches a finished OCR job and turns it into an on-device game record.
/// From here on the game is reviewed and corrected entirely offline.
Future<GameRecord> importOcrGame(WidgetRef ref, String backendGameId) async {
  final api = ref.read(apiServiceProvider);
  final session = await ref.read(sessionIdProvider.future);
  final remote = await api.getGame(backendGameId, session);
  final locale = ref.read(settingsProvider).locale;
  final tokens = [
    for (final m in [...remote.moves]
      ..sort((a, b) => a.ply_index.compareTo(b.ply_index)))
      m.is_legal && m.selected_san != null
          ? localizeSan(m.selected_san!, locale)
          : m.ocr_raw_text,
  ];
  return ref.read(gamesProvider.notifier).create(
        tokens: tokens,
        source: GameSource.ocr,
        locale: locale,
        headers: {
          if (remote.upload_metadata.filename != null)
            'Annotator': 'OCR: ${remote.upload_metadata.filename}',
        },
      );
}

class CropCornersNotifier extends AutoDisposeNotifier<List<Offset>> {
  @override
  List<Offset> build() =>
      const [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)];

  void init(Size containerSize) {
    final w = containerSize.width;
    final h = containerSize.height;
    state = [
      Offset(w * 0.05, h * 0.05),
      Offset(w * 0.95, h * 0.05),
      Offset(w * 0.95, h * 0.95),
      Offset(w * 0.05, h * 0.95),
    ];
  }

  void move(int index, Offset delta, Size bounds) {
    if (state.length != 4) return;
    final next = List<Offset>.of(state);
    next[index] = Offset(
      (next[index].dx + delta.dx).clamp(0.0, bounds.width),
      (next[index].dy + delta.dy).clamp(0.0, bounds.height),
    );
    state = next;
  }
}

final cropCornersProvider =
    NotifierProvider.autoDispose<CropCornersNotifier, List<Offset>>(
        CropCornersNotifier.new);

final cropImageBytesProvider = FutureProvider.autoDispose
    .family<PreparedCropImage, XFile>((ref, xFile) async {
  return compute(prepareCropImage, await xFile.readAsBytes());
});

/// Convenience used by the paywall/home to show the plan name.
String planNameFor(String? productId) {
  for (final p in kPlans) {
    if (p.productId == productId) return p.title;
  }
  return 'Pro';
}
