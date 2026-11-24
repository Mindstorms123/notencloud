import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:notencloud/models/musician_profile.dart';
import 'package:notencloud/models/setlist.dart';
import 'package:notencloud/models/song.dart';
import 'package:notencloud/services/storage_service.dart';
import 'package:notencloud/ui/widgets/setlist_export_sheet.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class _TempPathProvider extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  _TempPathProvider(this.dir);
  final Directory dir;

  @override
  Future<String?> getTemporaryPath() async => dir.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;
}

void main() {
  testWidgets('booklet for a substitute ends with the finished dialog, not a stuck progress window',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const profile = MusicianProfile(instrument: 'Trompete', voiceNumber: 2, keyOrClef: 'Bb');
    late StorageService storage;
    late Setlist setlist;

    await tester.runAsync(() async {
      await initializeDateFormatting('de_DE', null);
      final dir = await Directory.systemTemp.createTemp('notencloud_sheet_test');
      PathProviderPlatform.instance = _TempPathProvider(dir);
      SharedPreferences.setMockInitialValues({});
      storage = await StorageService.init();

      const part = PartFile(
        id: 'p1',
        songId: 'song_1',
        fileName: 'Trompete 2.pdf',
        remotePath: '/Noten/Marsch/Trompete 2.pdf',
        detectedInstrument: 'Trompete',
        detectedVoice: 2,
        detectedKey: 'Bb',
      );
      const song = Song(
        id: 'song_1',
        title: 'Marsch',
        folderName: 'Marsch',
        remoteFolderPath: '/Noten/Marsch',
        parts: [part],
      );
      await storage.saveCachedSongs([song]);

      // Die Stimme liegt bereits lokal vor (wie nach einem Download).
      final doc = PdfDocument();
      doc.pages.add().graphics.drawString('Trompete 2', PdfStandardFont(PdfFontFamily.helvetica, 16));
      final localPath = await storage.getLocalPdfPath(song.id, part.fileName, part: part);
      await File(localPath).writeAsBytes(await doc.save());
      doc.dispose();

      setlist = Setlist.create(
        title: 'Gala',
        items: [
          SetlistItem(id: 'i1', songId: song.id, songTitle: song.title, songFolderName: song.folderName, order: 1),
        ],
      );
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => SetlistExportSheet.show(
              context,
              setlist: setlist,
              currentProfile: profile,
              storageService: storage,
            ),
            child: const Text('export'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('export'));
    await tester.pumpAndSettle();

    final button = find.textContaining('erstellen & teilen');
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(button);
      // Erst das Schließen des Blatts zu Ende spielen (wie in der App, wo das
      // Erzeugen länger dauert als die Animation) …
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('erstellen & teilen'), findsNothing);
      // … dann echte Zeit für Dateizugriffe und PDF-Erzeugung; dazwischen Bilder zeichnen,
      // damit das Blatt wie in der App tatsächlich abgebaut wird.
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 100));
      }
    });
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Notenheft fertig!'), findsOneWidget);
    expect(find.text('Jetzt teilen'), findsOneWidget);
    expect(find.textContaining('Bereite'), findsNothing);
  });
}
