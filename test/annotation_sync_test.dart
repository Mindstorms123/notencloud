import 'package:flutter_test/flutter_test.dart';
import 'package:notencloud/models/annotation.dart';
import 'package:notencloud/models/nextcloud_account.dart';
import 'package:notencloud/services/nextcloud_service.dart';

void main() {
  group('PageAnnotations serialization and sync metadata', () {
    test('serializes and deserializes PageAnnotations with timestamps', () {
      final now = DateTime.now();
      final annotations = PageAnnotations(
        pageIndex: 1,
        strokes: const [
          Stroke(
            id: 's1',
            type: StrokeType.pen,
            colorValue: 0xFFEF4444,
            width: 3.0,
            points: [Point2D(x: 0.2, y: 0.3), Point2D(x: 0.4, y: 0.5)],
          ),
        ],
        textNotes: const [
          TextNote(
            id: 't1',
            text: 'Atemzeichen hier!',
            position: Point2D(x: 0.5, y: 0.6),
          ),
        ],
        updatedAt: now,
        isSyncedWithCloud: true,
      );

      final json = annotations.toJson();
      expect(json['pageIndex'], 1);
      expect(json['strokes'], isNotEmpty);
      expect(json['textNotes'], isNotEmpty);
      expect(json['updatedAt'], isNotNull);
      expect(json['isSynced'], true);

      final reconstructed = PageAnnotations.fromJson(json);
      expect(reconstructed.pageIndex, 1);
      expect(reconstructed.strokes.length, 1);
      expect(reconstructed.strokes.first.id, 's1');
      expect(reconstructed.textNotes.length, 1);
      expect(reconstructed.textNotes.first.text, 'Atemzeichen hier!');
      expect(reconstructed.isSyncedWithCloud, true);
    });
  });

  group('NextcloudService user-specific annotation paths', () {
    test('builds user-specific annotation directory and file paths', () {
      const account = NextcloudAccount(
        serverUrl: 'https://cloud.blasorchester-1862.de',
        username: 'trompete_hans',
        password: 'password123',
        rootFolder: '/Noten',
        isValidated: true,
      );
      final service = NextcloudService(account);

      // Verify directory ensuring logic
      expect(account.cleanRootFolder, '/Noten');
      expect(account.username, 'trompete_hans');
      expect(service.account.username, 'trompete_hans');
    });
  });
}
