import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/sse_service.dart';
import '../theme/arbiter_tokens.dart';

// ── Backend URL ───────────────────────────────────────────────────────────────

/// Base URL for the Arbiter AI backend.
///
/// Override at build time: `--dart-define=BACKEND_URL=http://192.168.1.1:8000`
const kBackendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'http://localhost:8000',
);

// ── Shared Dio instances ──────────────────────────────────────────────────────

final _regularDioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      baseUrl: kBackendUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
    ),
  );
});

final _streamDioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      baseUrl: kBackendUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 11),
    ),
  );
});

// ── Service providers ─────────────────────────────────────────────────────────

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService(ref.watch(_regularDioProvider));
});

final sseServiceProvider = Provider<SseService>((ref) {
  return SseService(ref.watch(_streamDioProvider));
});

// ── Image picker ──────────────────────────────────────────────────────────────

final imagePickerProvider = Provider<ImagePicker>((_) => ImagePicker());

// ── Anonymous session ID ──────────────────────────────────────────────────────

/// Stable for the lifetime of the app process.  Resets on restart.
/// Groups uploaded games together for the "Recent games" list.
final _sessionIdProvider = Provider<String>((_) {
  final rng = Random.secure();
  final bytes = List.generate(8, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
});

// ── Recent games ──────────────────────────────────────────────────────────────

/// Games uploaded in this session, most-recent first.
/// Auto-disposes so it re-fetches whenever the home screen re-enters the tree.
final recentGamesProvider = FutureProvider.autoDispose<List<GameSummary>>((ref) {
  final sessionId = ref.read(_sessionIdProvider);
  return ref.read(apiServiceProvider).getGames(sessionId);
});

// ── Game provider (family by gameId) ─────────────────────────────────────────

class GameNotifier
    extends AutoDisposeFamilyAsyncNotifier<GameAnalysisResponse, String> {
  @override
  Future<GameAnalysisResponse> build(String gameId) {
    return ref.watch(apiServiceProvider).getGame(gameId);
  }

  Future<void> correctMove(int plyIndex, String correctedSan) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(apiServiceProvider).correctMove(
            gameId: arg,
            plyIndex: plyIndex,
            correctedSan: correctedSan,
          ),
    );
  }
}

final gameProvider = AsyncNotifierProvider.autoDispose
    .family<GameNotifier, GameAnalysisResponse, String>(
  GameNotifier.new,
);

// ── SSE job status stream ─────────────────────────────────────────────────────

final jobStatusProvider =
    StreamProvider.autoDispose.family<JobStatusEvent, String>((ref, jobId) {
  // CancelToken aborts the in-flight HTTP GET immediately on provider dispose,
  // not just the stream subscription.
  final cancelToken = CancelToken();
  ref.onDispose(cancelToken.cancel);
  return ref
      .watch(sseServiceProvider)
      .watchJob(jobId, cancelToken: cancelToken);
});

// ── Upload provider ───────────────────────────────────────────────────────────

class UploadNotifier extends AutoDisposeAsyncNotifier<UploadResponse?> {
  @override
  Future<UploadResponse?> build() async => null;

  Future<void> upload(XFile file, {String locale = 'en'}) async {
    state = const AsyncLoading();
    final sessionId = ref.read(_sessionIdProvider);
    state = await AsyncValue.guard(
      () => ref.read(apiServiceProvider).uploadScoresheet(
            file: file,
            locale: locale,
            sessionId: sessionId,
          ),
    );
  }
}

final uploadProvider =
    AsyncNotifierProvider.autoDispose<UploadNotifier, UploadResponse?>(
  UploadNotifier.new,
);

// ── Crop corners provider ─────────────────────────────────────────────────────

class CropCornersNotifier extends AutoDisposeNotifier<List<Offset>> {
  @override
  List<Offset> build() => const [];

  void init(Size containerSize) {
    final w = containerSize.width;
    final h = containerSize.height;
    state = [
      Offset(w * 0.05, h * 0.05), // top-left
      Offset(w * 0.95, h * 0.05), // top-right
      Offset(w * 0.95, h * 0.95), // bottom-right
      Offset(w * 0.05, h * 0.95), // bottom-left
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
  CropCornersNotifier.new,
);

// ── Crop image bytes ──────────────────────────────────────────────────────────

final cropImageBytesProvider =
    FutureProvider.autoDispose.family<Uint8List, XFile>((ref, xFile) {
  return xFile.readAsBytes();
});

// ── Correction input provider ─────────────────────────────────────────────────

class CorrectionState {
  final String input;
  final List<String> suggestions;

  const CorrectionState({this.input = '', this.suggestions = const []});

  CorrectionState copyWith({String? input, List<String>? suggestions}) =>
      CorrectionState(
        input: input ?? this.input,
        suggestions: suggestions ?? this.suggestions,
      );
}

class CorrectionNotifier extends AutoDisposeNotifier<CorrectionState> {
  @override
  CorrectionState build() => const CorrectionState();

  void addChar(String char) =>
      state = state.copyWith(input: state.input + char);

  void backspace() {
    if (state.input.isEmpty) return;
    state =
        state.copyWith(input: state.input.substring(0, state.input.length - 1));
  }

  void clear() => state = state.copyWith(input: '');

  void fillSuggestion(String san) => state = state.copyWith(input: san);

  void setSuggestions(List<String> suggestions) =>
      state = state.copyWith(suggestions: suggestions);
}

final correctionProvider =
    NotifierProvider.autoDispose<CorrectionNotifier, CorrectionState>(
  CorrectionNotifier.new,
);

// ── Manual analysis ───────────────────────────────────────────────────────────

/// Drives the ManualEntryScreen → GameScreen flow.
///
/// Call [ManualAnalysisNotifier.analyze] to submit; the async state progresses
/// loading → data on success or error on failure.  AutoDispose means the result
/// is discarded when ManualEntryScreen leaves the tree.
class ManualAnalysisNotifier
    extends AutoDisposeAsyncNotifier<GameAnalysisResponse?> {
  @override
  Future<GameAnalysisResponse?> build() async => null;

  Future<void> analyze(List<String> moves, {String locale = 'en'}) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(apiServiceProvider).analyzeMovelist(
            moves: moves,
            locale: locale,
          ),
    );
  }
}

final manualAnalysisProvider = AsyncNotifierProvider.autoDispose<
    ManualAnalysisNotifier, GameAnalysisResponse?>(
  ManualAnalysisNotifier.new,
);

// ── Selected move index (game screen) ─────────────────────────────────────────

final selectedMoveIndexProvider = StateProvider.autoDispose<int>((_) => 0);

// ── Appearance settings (persisted) ───────────────────────────────────────────

/// Overridden in main() with the resolved [SharedPreferences] instance so the
/// settings notifier can read/write synchronously.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

const _kThemeModeKey = 'theme_mode';
const _kBoardPaletteKey = 'board_palette';

class AppSettings {
  final ThemeMode themeMode;
  final BoardPalette palette;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.palette = BoardPalette.wood,
  });

  AppSettings copyWith({ThemeMode? themeMode, BoardPalette? palette}) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        palette: palette ?? this.palette,
      );
}

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final prefs = ref.read(sharedPreferencesProvider);
    return AppSettings(
      themeMode: _parseEnum(
          prefs.getString(_kThemeModeKey), ThemeMode.values, ThemeMode.system),
      palette: _parseEnum(prefs.getString(_kBoardPaletteKey),
          BoardPalette.values, BoardPalette.wood),
    );
  }

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    ref.read(sharedPreferencesProvider).setString(_kThemeModeKey, mode.name);
  }

  void setPalette(BoardPalette palette) {
    state = state.copyWith(palette: palette);
    ref.read(sharedPreferencesProvider).setString(_kBoardPaletteKey, palette.name);
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

// ── Connectivity (offline banner) ─────────────────────────────────────────────

/// Emits `true` when the device has a network connection, `false` when offline.
/// Starts with the current state, then tracks changes. Display-only — uploads
/// and analysis still go through the backend and report their own errors.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  bool isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  yield isOnline(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(isOnline);
});
