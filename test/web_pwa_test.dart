import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notencloud/models/annotation.dart';
import 'package:notencloud/models/nextcloud_account.dart';
import 'package:notencloud/models/song.dart';
import 'package:notencloud/services/annotation_service.dart';
import 'package:notencloud/services/nextcloud_service.dart';
import 'package:notencloud/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late AnnotationService annotationService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    storage = StorageService(prefs);
    annotationService = AnnotationService(storage, isWeb: true);
  });

  group('Web PWA In-Memory & Preferences Score Cache Tests', () {
    test('StorageService caches and retrieves part bytes in memory for Web', () {
      expect(storage.hasCachedPartBytes('song_1', 'Flöte 1.pdf'), isFalse);
      expect(storage.getCachedPartBytes('song_1', 'Flöte 1.pdf'), isNull);

      final dummyBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]); // %PDF
      storage.cachePartBytes('song_1', 'Flöte 1.pdf', dummyBytes);

      expect(storage.hasCachedPartBytes('song_1', 'Flöte 1.pdf'), isTrue);
      expect(storage.getCachedPartBytes('song_1', 'Flöte 1.pdf'), equals(dummyBytes));
    });

    test('StorageService stores and manages web annotations via SharedPreferences', () async {
      expect(storage.getWebAnnotation('song_1', 'part_1', 1), isNull);

      const jsonStr = '{"pageIndex":1,"strokes":[{"id":"s1","type":"pen","colorValue":4278190080,"width":2.0,"points":[{"x":0.5,"y":0.5}]}]}';
      await storage.saveWebAnnotation('song_1', 'part_1', 1, jsonStr);

      expect(storage.getWebAnnotation('song_1', 'part_1', 1), equals(jsonStr));

      await storage.deleteWebAnnotation('song_1', 'part_1', 1);
      expect(storage.getWebAnnotation('song_1', 'part_1', 1), isNull);
    });

    test('AnnotationService saves and loads annotations in web mode', () async {
      final initial = await annotationService.loadAnnotations('song_test', 'part_test', 1);
      expect(initial.strokes, isEmpty);

      final annotations = PageAnnotations(
        pageIndex: 1,
        strokes: const [
          Stroke(
            id: 's_1',
            type: StrokeType.pen,
            colorValue: 0xFF000000,
            width: 3.0,
            points: [Point2D(x: 0.1, y: 0.2), Point2D(x: 0.3, y: 0.4)],
          ),
        ],
        textNotes: const [
          TextNote(
            id: 't_1',
            text: 'Crescendo!',
            position: Point2D(x: 0.2, y: 0.2),
          ),
        ],
      );

      final saveResult = await annotationService.saveAnnotations('song_test', 'part_test', annotations);
      expect(saveResult, isTrue);

      // Verify it was saved to storage
      final savedJson = storage.getWebAnnotation('song_test', 'part_test', 1);
      expect(savedJson, isNotNull);

      // Verify loadAnnotations retrieves it
      final loaded = await annotationService.loadAnnotations('song_test', 'part_test', 1);
      expect(loaded.strokes.length, equals(1));
      expect(loaded.strokes.first.id, equals('s_1'));
      expect(loaded.textNotes.length, equals(1));
      expect(loaded.textNotes.first.text, equals('Crescendo!'));

      // Verify clearPageAnnotations
      await annotationService.clearPageAnnotations('song_test', 'part_test', 1);
      expect(storage.getWebAnnotation('song_test', 'part_test', 1), isNull);
    });
  });

  group('NextcloudService downloadPartBytes Tests', () {
    test('downloadPartBytes streams and returns Uint8List directly', () async {
      final mockData = utf8.encode('%PDF-1.4 dummy score content');
      final mockClient = MockClient((request) async {
        final decodedPath = Uri.decodeComponent(request.url.path);
        if (decodedPath.endsWith('Flöte_1.pdf')) {
          return http.Response.bytes(mockData, 200, headers: {'content-length': '${mockData.length}'});
        }
        return http.Response('Not Found: ${request.url.path}', 404);
      });

      const account = NextcloudAccount(
        serverUrl: 'https://cloud.blasorchester-1862.de',
        username: 'musiker',
        password: 'secret_password',
        rootFolder: '/Noten',
      );

      final service = NextcloudService(account, mockClient);
      const part = PartFile(
        id: 'p1',
        songId: 's1',
        fileName: 'Flöte 1.pdf',
        remotePath: '/remote.php/dav/files/musiker/Noten/Song1/Flöte_1.pdf',
        detectedInstrument: 'Flöte',
        detectedVoice: 1,
      );

      double lastProgress = 0.0;
      final bytes = await service.downloadPartBytes(part, onProgress: (p) => lastProgress = p);

      expect(bytes, isNotNull);
      expect(bytes.length, equals(mockData.length));
      expect(utf8.decode(bytes), equals('%PDF-1.4 dummy score content'));
      expect(lastProgress, equals(1.0));
    });
  });
}
