import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile/providers/providers.dart';
import 'package:mobile/services/crop_service.dart';
import 'package:mobile/services/sse_service.dart';

class SequenceAdapter implements HttpClientAdapter {
  final List<String> responses;
  int calls = 0;
  SequenceAdapter(this.responses);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = utf8.encode(responses[calls++]);
    return ResponseBody(
      Stream.fromIterable(bytes.map((b) => Uint8List.fromList([b]))),
      200,
      headers: {
        Headers.contentTypeHeader: ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('anonymous owner survives a new provider container', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ProviderContainer container() => ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    final first = container();
    final id = await first.read(sessionIdProvider.future);
    first.dispose();
    final second = container();
    addTearDown(second.dispose);
    expect(await second.read(sessionIdProvider.future), id);
    expect(id.length, 32);
  });

  test('crop changes image content and dimensions', () {
    final image = img.Image(width: 100, height: 100, numChannels: 3);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(
      image,
      x1: 25,
      y1: 25,
      x2: 74,
      y2: 74,
      color: img.ColorRgb8(0, 0, 0),
    );
    final result = img.decodeJpg(
      rectifyCrop((
        img.encodePng(image),
        const [
          Offset(0.3, 0.3),
          Offset(0.7, 0.3),
          Offset(0.7, 0.7),
          Offset(0.3, 0.7),
        ],
      )),
    )!;
    expect(result.width, 41);
    expect(result.height, 41);
    expect(result.getPixel(0, 0).r, lessThan(10));
  });

  test('crossed crop corners are rejected', () {
    expect(
      () => rectifyCrop((
        Uint8List(0),
        const [Offset(0, 0), Offset(1, 1), Offset(1, 0), Offset(0, 1)],
      )),
      throwsFormatException,
    );
  });

  test('SSE reconnects after timeout and decodes split UTF-8', () async {
    final adapter = SequenceAdapter([
      'data: {"job_id":"j","status":"timeout"}\n\n',
      'data: {"job_id":"j","status":"failed","error_message":"Şah"}\r\n\r\n',
    ]);
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(dio.close);
    final events = await SseService(
      dio,
      retryDelay: Duration.zero,
    ).watchJob('j').toList();
    expect(adapter.calls, 2);
    expect(events.single.error_message, 'Şah');
    expect(events.single.status, 'failed');
  });

  test('SSE gives a recoverable error after bounded reconnects', () async {
    final adapter = SequenceAdapter(List.filled(4, ': keepalive\n\n'));
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(dio.close);
    await expectLater(
      SseService(dio, retryDelay: Duration.zero).watchJob('j').toList(),
      throwsStateError,
    );
    expect(adapter.calls, 4);
  });
}
