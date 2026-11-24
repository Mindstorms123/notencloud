import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notencloud/models/annotation.dart';
import 'package:notencloud/models/nextcloud_account.dart';
import 'package:notencloud/services/annotation_service.dart';
import 'package:notencloud/services/nextcloud_service.dart';
import 'package:notencloud/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Nextcloud-Attrappe mit schaltbarer Verbindung.
class Cloud {
  bool online = false;
  final dirs = <String>{'/remote.php/dav/files/leon'};
  final files = <String, String>{};

  Future<http.Response> handle(http.Request request) async {
    if (!online) throw const SocketException('Failed host lookup');
    final path = Uri.decodeFull(request.url.path);
    switch (request.method) {
      case 'PROPFIND':
        return http.Response('', dirs.contains(path) ? 207 : 404);
      case 'MKCOL':
        // Der Notenordner ist für dieses Konto gesperrt.
        if (path.contains('/Noten')) return http.Response('', 403);
        dirs.add(path);
        return http.Response('', 201);
      case 'PUT':
        if (path.contains('/Noten/')) return http.Response('', 403);
        files[path] = request.body;
        return http.Response('', 201);
      case 'GET':
        final content = files[path];
        return content == null ? http.Response('', 404) : http.Response(content, 200);
    }
    return http.Response('', 405);
  }
}

PageAnnotations note(int minute) => PageAnnotations(
      pageIndex: 1,
      strokes: const [],
      textNotes: const [],
      updatedAt: DateTime(2026, 11, 24, 20, minute),
    );

void main() {
  const file = '/remote.php/dav/files/leon/_Notizen/leon/Marsch/Marsch-Tuba_p1.json';
  late Cloud cloud;
  late StorageService storage;
  late AnnotationService annotations;
  late NextcloudService nextcloud;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService(await SharedPreferences.getInstance());
    annotations = AnnotationService(storage, isWeb: true);
    cloud = Cloud();
    nextcloud = NextcloudService(
      const NextcloudAccount(
        serverUrl: 'https://cloud.example.org',
        username: 'leon',
        password: 'geheim',
        rootFolder: '/Noten',
        isValidated: true,
      ),
      MockClient(cloud.handle),
    );
  });

  test('a note made without internet is uploaded once the connection is back', () async {
    // Probe ohne Internet
    final saved = await annotations.saveAnnotations('Marsch', 'Marsch-Tuba', note(0), nextcloudService: nextcloud);
    expect(saved, isFalse);
    expect(nextcloud.lastAnnotationUploadOffline, isTrue);
    expect(storage.getPendingAnnotationUploads(), [(songId: 'Marsch', partId: 'Marsch-Tuba', pageIndex: 1)]);

    // Noch immer offline: bleibt vorgemerkt
    expect(await annotations.syncPendingUploads(nextcloud), 0);
    expect(storage.getPendingAnnotationUploads(), hasLength(1));

    // Wieder online
    cloud.online = true;
    expect(await annotations.syncPendingUploads(nextcloud), 1);
    expect(cloud.files[file], contains('T20:00'));
    expect(storage.getPendingAnnotationUploads(), isEmpty);
  });

  test('a newer note from another device is not overwritten', () async {
    await annotations.saveAnnotations('Marsch', 'Marsch-Tuba', note(0), nextcloudService: nextcloud);
    expect(storage.getPendingAnnotationUploads(), hasLength(1));

    // Inzwischen hat ein anderes Gerät eine spätere Fassung gespeichert.
    cloud.online = true;
    final other = NextcloudService(nextcloud.account, MockClient(cloud.handle));
    expect(await other.uploadPageAnnotations('Marsch', 'Marsch-Tuba', note(30)), isTrue);

    expect(await annotations.syncPendingUploads(nextcloud), 0);
    expect(cloud.files[file], contains('T20:30'));
    expect(storage.getPendingAnnotationUploads(), isEmpty);
  });

  test('a note saved online is not queued', () async {
    cloud.online = true;
    expect(await annotations.saveAnnotations('Marsch', 'Marsch-Tuba', note(0), nextcloudService: nextcloud), isTrue);
    expect(storage.getPendingAnnotationUploads(), isEmpty);
  });
}
