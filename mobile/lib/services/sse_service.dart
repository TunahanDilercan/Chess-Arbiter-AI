import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/models.dart';

class SseService {
  final Dio _dio;
  final Duration retryDelay;

  SseService(this._dio, {this.retryDelay = const Duration(seconds: 2)});

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
    Object? lastError;
    for (var attempt = 0; attempt < 4; attempt++) {
      if (cancelToken?.isCancelled ?? false) return;
      try {
        final response = await _dio.get<ResponseBody>(
          '/api/sse/$jobId',
          cancelToken: cancelToken,
          options: Options(
            responseType: ResponseType.stream,
            receiveTimeout: const Duration(seconds: 30),
          ),
        );
        final body = response.data;
        if (body != null) {
          // Stateful UTF-8 decoding handles characters split between packets.
          final lines = utf8.decoder
              .bind(body.stream)
              .transform(const LineSplitter());
          final data = <String>[];
          await for (final line in lines.timeout(const Duration(seconds: 30))) {
            if (cancelToken?.isCancelled ?? false) return;
            if (line.startsWith('data:')) {
              data.add(line.substring(5).trimLeft());
            } else if (line.isEmpty && data.isNotEmpty) {
              JobStatusEvent? event;
              try {
                event = JobStatusEvent.fromJson(
                  jsonDecode(data.join('\n')) as Map<String, dynamic>,
                );
              } on FormatException {
                // Ignore malformed events without dropping the connection.
              } finally {
                data.clear();
              }
              if (event == null) continue;
              if (event.status == 'timeout') break;
              yield event;
              if (event.status == 'completed' || event.status == 'failed') {
                return;
              }
            }
          }
        }
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) return;
        if (error.response?.statusCode == 404) rethrow;
        lastError = error;
      } on TimeoutException catch (error) {
        lastError = error;
      }
      if (attempt < 3) await Future<void>.delayed(retryDelay);
    }
    throw StateError(
      'Status connection lost. Reconnect to check this job. ${lastError ?? ''}',
    );
  }
}
