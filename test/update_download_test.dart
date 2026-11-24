import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notencloud/services/update_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _TempPathProvider extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  _TempPathProvider(this.dir);
  final Directory dir;

  @override
  Future<String?> getTemporaryPath() async => dir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  final apk = List<int>.generate(5000, (i) => i % 251);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('notencloud_update_test');
    PathProviderPlatform.instance = _TempPathProvider(dir);
  });

  tearDown(() => dir.delete(recursive: true));

  test('resumes where the connection dropped instead of failing', () async {
    final requests = <String?>[];
    final client = MockClient.streaming((request, _) async {
      final range = request.headers['Range'];
      requests.add(range);
      if (range == null) {
        // Erste Verbindung reißt nach 2000 Bytes ab (Handy geht aus).
        final controller = StreamController<List<int>>();
        controller.add(apk.sublist(0, 2000));
        scheduleMicrotask(() {
          controller.addError(const SocketException('Connection closed'));
          controller.close();
        });
        return http.StreamedResponse(controller.stream, 200, contentLength: apk.length);
      }
      final start = int.parse(range.replaceAll('bytes=', '').replaceAll('-', ''));
      final rest = apk.sublist(start);
      return http.StreamedResponse(Stream.value(rest), 206, contentLength: rest.length);
    });

    final progress = <double>[];
    final file = await UpdateService(client).downloadApk(
      'https://example.org/app.apk',
      onProgress: progress.add,
      retryDelay: Duration.zero,
    );

    expect(requests, [null, 'bytes=2000-']);
    expect(await file.readAsBytes(), apk);
    expect(progress.last, 1.0);
  });

  test('starts over when the server does not support resuming', () async {
    var calls = 0;
    final client = MockClient.streaming((request, _) async {
      calls++;
      if (calls == 1) {
        final controller = StreamController<List<int>>();
        controller.add(apk.sublist(0, 1000));
        scheduleMicrotask(() {
          controller.addError(const SocketException('Connection closed'));
          controller.close();
        });
        return http.StreamedResponse(controller.stream, 200, contentLength: apk.length);
      }
      return http.StreamedResponse(Stream.value(apk), 200, contentLength: apk.length);
    });

    final file = await UpdateService(client).downloadApk('https://example.org/app.apk', retryDelay: Duration.zero);
    expect(await file.readAsBytes(), apk);
  });

  test('gives up with an error after repeated failures', () async {
    final client = MockClient.streaming((request, _) async => http.StreamedResponse(const Stream.empty(), 503));
    await expectLater(
      UpdateService(client).downloadApk('https://example.org/app.apk', maxAttempts: 3, retryDelay: Duration.zero),
      throwsA(isA<Exception>()),
    );
  });
}
