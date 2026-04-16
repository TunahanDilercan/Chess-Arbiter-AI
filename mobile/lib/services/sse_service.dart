import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/models.dart';

class SseService {
  final Dio _dio;

  SseService(this._dio);

  /// Stream real-time [JobStatusEvent]s from the backend SSE endpoint.
  ///
  /// Emits the current DB snapshot immediately, then every Redis pub/sub event
  /// until the terminal status (`completed` or `failed`) is received.
  /// The stream closes when the backend closes the connection or on error.
  ///
  /// Pass a [cancelToken] (typically from `ref.onDispose`) to abort the
  /// in-flight HTTP request immediately when the provider is disposed.
  Stream<JobStatusEvent> watchJob(
    String jobId, {
    CancelToken? cancelToken,
  }) async* {
    final Response<ResponseBody> response;
    try {
      response = await _dio.get<ResponseBody>(
        '/api/sse/$jobId',
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(minutes: 11),
        ),
      );
    } on DioException catch (e) {
      // Normal cancellation during provider dispose — exit cleanly.
      if (CancelToken.isCancel(e)) return;
      rethrow;
    }

    final body = response.data;
    if (body == null) return;

    var buffer = '';

    await for (final chunk in body.stream) {
      buffer += utf8.decode(chunk);

      // SSE events are separated by double-newlines.
      while (buffer.contains('\n\n')) {
        final idx = buffer.indexOf('\n\n');
        final eventText = buffer.substring(0, idx);
        buffer = buffer.substring(idx + 2);

        for (final line in eventText.split('\n')) {
          if (!line.startsWith('data: ')) continue;
          try {
            final payload =
                jsonDecode(line.substring(6)) as Map<String, dynamic>;
            yield JobStatusEvent.fromJson(payload);
          } catch (_) {
            // Malformed JSON — skip.
          }
        }
      }
    }
  }
}
