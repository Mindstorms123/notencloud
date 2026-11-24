import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:notencloud/models/annotation.dart';
import 'package:notencloud/models/song.dart';
import 'package:notencloud/services/annotation_service.dart';
import 'package:notencloud/services/storage_service.dart';
import 'package:notencloud/services/voice_matcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // Verzeichnis eines Geräts, das die Stimme noch unter der Kennung führt, die
  // beim ersten Einlesen galt (Stück-Kennung ohne Ordner davor).
  const currentSongId = '01_Aktuelle Noten_Marsch';
  const staleSong = Song(
    id: currentSongId,
    title: 'Marsch',
    folderName: 'Marsch',
    remoteFolderPath: '/Noten/01_Aktuelle Noten/Marsch',
    category: 'Aktuelle Noten',
    parts: [
      PartFile(
        id: 'Marsch-alt',
        songId: 'Marsch',
        fileName: 'Trompete 2 in Bb.pdf',
        remotePath: '/Noten/01_Aktuelle Noten/Marsch/Trompete 2 in Bb.pdf',
        detectedInstrument: 'Trompete',
        detectedVoice: 2,
      ),
    ],
  );

  test('devices with an old library agree on part ids and keep their notes', () async {
    SharedPreferences.setMockInitialValues({
      'cached_songs_index': jsonEncode([staleSong.toJson()]),
    });
    final storage = StorageService(await SharedPreferences.getInstance());

    final freshId =
        VoiceMatcher.parsePartFileName('Trompete 2 in Bb.pdf', currentSongId, staleSong.parts.first.remotePath).id;
    final part = storage.getCachedSongs().single.parts.single;

    // Gleiche Kennung wie auf einem frisch eingerichteten Gerät
    expect(part.id, freshId);
    expect(part.songId, currentSongId);
    expect(storage.getLegacyPartId(freshId), (songId: 'Marsch', partId: 'Marsch-alt'));

    // Eine Notiz von früher liegt noch unter der alten Kennung …
    final annotations = AnnotationService(storage, isWeb: true);
    final oldNote = PageAnnotations(
      pageIndex: 1,
      textNotes: const [],
      strokes: const [],
      updatedAt: DateTime(2026, 11, 1),
    );
    await annotations.saveAnnotations('Marsch', 'Marsch-alt', oldNote);

    // … und wird unter der neuen wiedergefunden und übernommen.
    final loaded = await annotations.loadAnnotations(currentSongId, freshId, 1);
    expect(loaded.updatedAt, DateTime(2026, 11, 1));
    expect(storage.getWebAnnotation(currentSongId, freshId, 1), isNotNull);
  });

  test('a current library is left untouched', () async {
    final id = VoiceMatcher.parsePartFileName('Tuba 1.pdf', currentSongId, '/Noten/x/Tuba 1.pdf').id;
    final song = Song(
      id: currentSongId,
      title: 'Marsch',
      folderName: 'Marsch',
      remoteFolderPath: '/Noten/x',
      parts: [
        PartFile(id: id, songId: currentSongId, fileName: 'Tuba 1.pdf', remotePath: '/Noten/x/Tuba 1.pdf'),
      ],
    );
    SharedPreferences.setMockInitialValues({'cached_songs_index': jsonEncode([song.toJson()])});
    final storage = StorageService(await SharedPreferences.getInstance());
    expect(storage.getCachedSongs().single.parts.single.id, id);
    expect(storage.getLegacyPartId(id), isNull);
  });
}
