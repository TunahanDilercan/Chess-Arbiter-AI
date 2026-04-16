import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import '../models/models.dart';

class ApiService {
  final Dio _dio;

  ApiService(this._dio);

  // ── Upload ──────────────────────────────────────────────────────────────────

  Future<UploadResponse> uploadScoresheet({
    required XFile file,
    String locale = 'en',
    String? sessionId,
  }) async {
    final bytes = await file.readAsBytes();
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: file.name,
        contentType: DioMediaType.parse(file.mimeType ?? 'image/jpeg'),
      ),
      'locale': locale,
      // ignore: use_null_aware_elements
      if (sessionId != null) 'session_id': sessionId,
    });
    final response = await _dio.post<dynamic>('/api/upload', data: formData);
    return UploadResponse.fromJson(response.data as Map<String, dynamic>);
  }

  // ── Games ───────────────────────────────────────────────────────────────────

  Future<GameAnalysisResponse> getGame(String gameId) async {
    final response = await _dio.get<dynamic>('/api/games/$gameId');
    return GameAnalysisResponse.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<GameSummary>> getGames(String sessionId) async {
    final response = await _dio.get<dynamic>(
      '/api/games',
      queryParameters: {'session_id': sessionId},
    );
    return (response.data as List<dynamic>)
        .map((e) => GameSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Stateless analysis ─────────────────────────────────────────────────────

  Future<GameAnalysisResponse> analyzeMovelist({
    required List<String> moves,
    String locale = 'en',
    String? sessionId,
  }) async {
    final response = await _dio.post<dynamic>(
      '/api/games/analyze',
      data: {
        'moves': moves,
        'locale': locale,
        // ignore: use_null_aware_elements
        if (sessionId != null) 'session_id': sessionId,
      },
    );
    return GameAnalysisResponse.fromJson(response.data as Map<String, dynamic>);
  }

  // ── Correction ──────────────────────────────────────────────────────────────

  Future<GameAnalysisResponse> correctMove({
    required String gameId,
    required int plyIndex,
    required String correctedSan,
    String locale = 'en',
  }) async {
    final response = await _dio.post<dynamic>(
      '/api/games/$gameId/moves/$plyIndex/correct',
      data: {'corrected_san': correctedSan, 'locale': locale},
    );
    return GameAnalysisResponse.fromJson(response.data as Map<String, dynamic>);
  }
}
