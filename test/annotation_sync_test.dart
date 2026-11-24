import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notencloud/models/annotation.dart';
import 'package:notencloud/models/nextcloud_account.dart';
import 'package:notencloud/services/nextcloud_service.dart';

/// Kleine Nextcloud-Attrappe: Ordner und Dateien im Speicher, der Notenordner
/// auf Wunsch schreibgeschützt.
class FakeCloud {
  FakeCloud({required this.notesReadOnly});

  final bool notesReadOnly;
  final dirs = <String>{'/remote.php/dav/files/leon', '/remote.php/dav/files/leon/Noten'};
  final files = <String, String>{};
  final log = <String>[];

  bool _protected(String path) => notesReadOnly && path.startsWith('/remote.php/dav/files/leon/Noten/');

  Future<http.Response> handle(http.Request request) async {
    final path = Uri.decodeFull(request.url.path);
    log.add('${request.method} $path');
    switch (request.method) {
      case 'PROPFIND':
        return http.Response('', dirs.contains(path) || files.containsKey(path) ? 207 : 404);
      case 'MKCOL':
        if (_protected(path)) return http.Response('', 403);
        dirs.add(path);
        return http.Response('', 201);
      case 'PUT':
        if (_protected(path)) return http.Response('', 403);
        final parent = path.substring(0, path.lastIndexOf('/'));
        if (!dirs.contains(parent)) return http.Response('', 409);
        final existed = files.containsKey(path);
        files[path] = request.body;
        return http.Response('', existed ? 204 : 201);
      case 'GET':
        final content = files[path];
        return content == null
            ? http.Response('', 404)
            : http.Response(content, 200, headers: {'content-type': 'application/json; charset=utf-8'});
      case 'DELETE':
        if (_protected(path)) return http.Response('', 403);
        return http.Response('', files.remove(path) == null ? 404 : 204);
    }
    return http.Response('', 405);
  }
}

NextcloudService serviceFor(FakeCloud cloud) => NextcloudService(
      const NextcloudAccount(
        serverUrl: 'https://cloud.example.org',
        username: 'leon',
        password: 'geheim',
        rootFolder: '/Noten',
        isValidated: true,
      ),
      MockClient(cloud.handle),
    );

PageAnnotations note(int minute) => PageAnnotations(
      pageIndex: 1,
      strokes: const [],
      textNotes: const [],
      updatedAt: DateTime(2026, 11, 24, 12, minute),
    );

void main() {
  const userArea = '/remote.php/dav/files/leon/_Notizen/leon/Marsch/Marsch-Tuba_p1.json';
  const notesFolder = '/remote.php/dav/files/leon/Noten/_Notizen/leon/Marsch/Marsch-Tuba_p1.json';

  test('notes reach other devices even when the notes folder is read-only', () async {
    final cloud = FakeCloud(notesReadOnly: true);

    // Gerät 1 (z. B. iPad) speichert eine Notiz.
    final ipad = serviceFor(cloud);
    expect(await ipad.uploadPageAnnotations('Marsch', 'Marsch-Tuba', note(0)), isTrue);
    expect(ipad.lastAnnotationUploadError, isNull);
    expect(cloud.files.keys, [userArea]);

    // Die nächste Notiz geht ohne Umweg über den gesperrten Ordner.
    cloud.log.clear();
    expect(await ipad.uploadPageAnnotations('Marsch', 'Marsch-Tuba', note(5)), isTrue);
    expect(cloud.log.where((l) => l.contains('/Noten/')), isEmpty);

    // Gerät 2 (z. B. Handy) findet sie.
    final phone = serviceFor(cloud);
    final loaded = await phone.downloadPageAnnotations('Marsch', 'Marsch-Tuba', 1);
    expect(loaded?.updatedAt, DateTime(2026, 11, 24, 12, 5));

    // Löschen entfernt sie wieder.
    expect(await phone.deletePageAnnotations('Marsch', 'Marsch-Tuba', 1), isTrue);
    expect(cloud.files, isEmpty);
  });

  test('a writable notes folder is still used, and the newest copy wins when both exist', () async {
    final cloud = FakeCloud(notesReadOnly: false);
    final service = serviceFor(cloud);
    expect(await service.uploadPageAnnotations('Marsch', 'Marsch-Tuba', note(0)), isTrue);
    expect(cloud.files.keys, [notesFolder]);

    // Ein anderes Gerät hat später eine neuere Fassung im eigenen Bereich abgelegt.
    cloud.dirs.addAll([
      '/remote.php/dav/files/leon/_Notizen',
      '/remote.php/dav/files/leon/_Notizen/leon',
      '/remote.php/dav/files/leon/_Notizen/leon/Marsch',
    ]);
    cloud.files[userArea] = cloud.files[notesFolder]!.replaceFirst('T12:00', 'T12:30');
    final loaded = await service.downloadPageAnnotations('Marsch', 'Marsch-Tuba', 1);
    expect(loaded?.updatedAt, DateTime(2026, 11, 24, 12, 30));
  });

  test('explains the failure when nothing is writable', () async {
    final cloud = FakeCloud(notesReadOnly: true)..dirs.clear();
    final service = NextcloudService(
      const NextcloudAccount(
        serverUrl: 'https://cloud.example.org',
        username: 'leon',
        password: 'geheim',
        rootFolder: '/Noten',
        isValidated: true,
      ),
      MockClient((request) async => http.Response('', request.method == 'PROPFIND' ? 404 : 403)),
    );
    expect(await service.uploadPageAnnotations('Marsch', 'Marsch-Tuba', note(0)), isFalse);
    expect(service.lastAnnotationUploadError, contains('nicht anlegen'));
    expect(cloud.files, isEmpty);
  });
}
