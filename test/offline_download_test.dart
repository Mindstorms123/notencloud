import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notencloud/models/song.dart';
import 'package:notencloud/services/storage_service.dart';

class FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String path;
  FakePathProviderPlatform(this.path);

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late StorageService storageService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('notencloud_offline_test_');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
    SharedPreferences.setMockInitialValues({});
    storageService = await StorageService.init();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('StorageService Offline & Legacy Score Resolution', () {
    test('returns target path directly when canonical file exists', () async {
      final songId = '01_Aktuelle Noten_Waterloo';
      final fileName = 'Trompete 1 in Bb.pdf';

      // Pre-create canonical file
      final dir = Directory('${tempDir.path}/scores/01_Aktuelle Noten_Waterloo');
      await dir.create(recursive: true);
      final file = File('${dir.path}/Trompete 1 in Bb.pdf');
      await file.writeAsString('dummy content');

      final resolvedPath = await storageService.getLocalPdfPath(songId, fileName);
      expect(resolvedPath, file.path);
      expect(await File(resolvedPath).exists(), isTrue);
    });

    test('resolves and renames legacy file with song title prefix', () async {
      final songId = '02_Ältere Noten_80er KULT(tour)';
      final canonicalName = 'Trompete 1 in Bb.pdf';
      final safeSongDir = '02__ltere Noten_80er KULT_tour_';

      // Create legacy file
      final dir = Directory('${tempDir.path}/scores/$safeSongDir');
      await dir.create(recursive: true);
      final legacyFile = File('${dir.path}/80er KULT_tour_ - Trompete 1 in Bb.pdf');
      await legacyFile.writeAsString('score content');

      expect(await legacyFile.exists(), isTrue);

      final resolvedPath = await storageService.getLocalPdfPath(songId, canonicalName);
      expect(resolvedPath, '${dir.path}/Trompete 1 in Bb.pdf');
      expect(await File(resolvedPath).exists(), isTrue);
      // Legacy file should be renamed to canonical
      expect(await legacyFile.exists(), isFalse);
    });

    test('isPartDownloaded returns true when legacy file exists and is resolved', () async {
      final songId = '01_Aktuelle Noten_Cheap Thrills';
      final canonicalName = 'Trompete 1 in Bb.pdf';

      final dir = Directory('${tempDir.path}/scores/01_Aktuelle Noten_Cheap Thrills');
      await dir.create(recursive: true);
      final legacyFile = File('${dir.path}/Cheap Thrills - Trompete 1 in Bb.pdf');
      await legacyFile.writeAsString('cheap thrills trump 1');

      final isDownloaded = await storageService.isPartDownloaded(songId, canonicalName);
      expect(isDownloaded, isTrue);
      expect(await File('${dir.path}/Trompete 1 in Bb.pdf').exists(), isTrue);
    });

    test('migrateAndDeduplicateScores cleans redundant duplicate legacy files', () async {
      final songId = '01_Aktuelle Noten_Aladdin';
      final dir = Directory('${tempDir.path}/scores/01_Aktuelle Noten_Aladdin');
      await dir.create(recursive: true);

      // Both canonical and duplicate legacy exist
      final canonicalFile = File('${dir.path}/Trompete 1 in Bb.pdf');
      await canonicalFile.writeAsString('canonical score');
      final legacyFile = File('${dir.path}/Aladdin - Trompete 1 in Bb.pdf');
      await legacyFile.writeAsString('redundant score');

      final song = Song(
        id: songId,
        title: 'Aladdin',
        folderName: 'Aladdin',
        remoteFolderPath: '/Noten/Aladdin',
        parts: [
          PartFile(
            id: 'p1',
            songId: songId,
            fileName: 'Trompete 1 in Bb.pdf',
            remotePath: '/Noten/Aladdin/Trompete/Trompete 1 in Bb.pdf',
            detectedInstrument: 'Trompete',
            detectedVoice: 1,
            detectedKey: 'Bb',
          ),
        ],
      );

      final cleanedCount = await storageService.migrateAndDeduplicateScores([song]);
      expect(cleanedCount, 1);
      expect(await canonicalFile.exists(), isTrue);
      expect(await legacyFile.exists(), isFalse);
    });
  });
}
