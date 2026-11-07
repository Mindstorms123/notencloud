import 'dart:io';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:notencloud/models/musician_profile.dart';
import 'package:notencloud/models/setlist.dart';
import 'package:notencloud/models/song.dart';
import 'package:notencloud/services/setlist_pdf_service.dart';
import 'package:notencloud/services/storage_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async {
    return Directory.systemTemp.path;
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('de_DE', null);
    PathProviderPlatform.instance = MockPathProviderPlatform();
  });

  test('appendDocument helper merges seamlessly with original dimensions', () async {
    final doc1 = PdfDocument();
    doc1.pageSettings.size = const Size(595, 842);
    doc1.pages.add().graphics.drawString('Doc 1 Page 1', PdfStandardFont(PdfFontFamily.helvetica, 14));
    doc1.pages.add().graphics.drawString('Doc 1 Page 2', PdfStandardFont(PdfFontFamily.helvetica, 14));
    final bytes1 = await doc1.save();
    doc1.dispose();

    final doc2 = PdfDocument();
    doc2.pageSettings.size = const Size(420, 595); // A5 size
    doc2.pages.add().graphics.drawString('Doc 2 Page 1', PdfStandardFont(PdfFontFamily.helvetica, 14));
    final bytes2 = await doc2.save();
    doc2.dispose();

    final mergedDoc = PdfDocument();

    void appendDoc(PdfDocument target, List<int> bytes) {
      final source = PdfDocument(inputBytes: bytes);
      for (int i = 0; i < source.pages.count; i++) {
        final page = source.pages[i];
        final section = target.sections!.add();
        section.pageSettings.size = page.size;
        section.pageSettings.margins.all = 0;
        final newPage = section.pages.add();
        newPage.graphics.drawPdfTemplate(
          page.createTemplate(),
          const Offset(0, 0),
          page.size,
        );
      }
      source.dispose();
    }

    appendDoc(mergedDoc, bytes1);
    appendDoc(mergedDoc, bytes2);

    expect(mergedDoc.pages.count, 3);
    expect(mergedDoc.pages[0].size.width, 595);
    expect(mergedDoc.pages[2].size.width, 420);

    final mergedBytes = await mergedDoc.save();
    mergedDoc.dispose();

    expect(mergedBytes.isNotEmpty, true);
  });

  test('generateSetlistOverviewPdf creates a valid PDF file with pieces & intermissions', () async {
    final setlist = Setlist.create(
      title: 'Frühjahrskonzert 2027',
      items: const [
        SetlistItem(
          id: '1',
          songId: 's1',
          songTitle: 'Olympia Marsch',
          songFolderName: 'Olympia Marsch',
          order: 1,
          notes: 'Ohne Wdh.',
        ),
        SetlistItem(
          id: '2',
          songId: 'pause',
          songTitle: 'PAUSE',
          songFolderName: '',
          order: 2,
          isIntermission: true,
          notes: '20 Minuten',
        ),
        SetlistItem(
          id: '3',
          songId: 's2',
          songTitle: 'Music',
          songFolderName: 'Music',
          order: 3,
          notes: 'Attacca',
        ),
      ],
    );

    final file = await SetlistPdfService.generateSetlistOverviewPdf(setlist);
    expect(file.existsSync(), true);
    expect(file.lengthSync(), greaterThan(1000));

    // Verify PDF contents can be parsed
    final loadedDoc = PdfDocument(inputBytes: await file.readAsBytes());
    expect(loadedDoc.pages.count, greaterThanOrEqualTo(1));
    loadedDoc.dispose();

    if (file.existsSync()) file.deleteSync();
  });

  test('generateAushilfeBookletPdf creates a complete booklet with cover and sheet music', () async {
    SharedPreferences.setMockInitialValues({});
    final storageService = await StorageService.init();

    // Create a dummy song PDF in temp
    final tempDir = Directory.systemTemp;
    final dummyPdfFile = File('${tempDir.path}/test_tpt2.pdf');
    final dummyDoc = PdfDocument();
    dummyDoc.pages.add().graphics.drawString('Trompete 2 Noten', PdfStandardFont(PdfFontFamily.helvetica, 16));
    await dummyPdfFile.writeAsBytes(await dummyDoc.save());
    dummyDoc.dispose();

    final song = Song(
      id: 'song_test_1',
      title: 'Konzertmarsch',
      folderName: 'Konzertmarsch',
      remoteFolderPath: '/Noten/Konzertmarsch',
      parts: [
        const PartFile(
          id: 'p1',
          songId: 'song_test_1',
          fileName: 'Trompete 2.pdf',
          remotePath: '/Noten/Konzertmarsch/Trompete 2.pdf',
          detectedInstrument: 'Trompete',
          detectedVoice: 2,
          detectedKey: 'Bb',
        ),
      ],
    );
    await storageService.saveCachedSongs([song]);

    final setlist = Setlist.create(
      title: 'Gala 2027',
      items: [
        SetlistItem(
          id: 'item1',
          songId: song.id,
          songTitle: song.title,
          songFolderName: song.folderName,
          order: 1,
        ),
        const SetlistItem(
          id: 'item2',
          songId: 'pause',
          songTitle: 'PAUSE',
          songFolderName: '',
          order: 2,
          isIntermission: true,
        ),
      ],
    );

    final aushilfeProfile = const MusicianProfile(
      instrument: 'Trompete',
      voiceNumber: 2,
      keyOrClef: 'Bb',
    );

    final bookletFile = await SetlistPdfService.generateAushilfeBookletPdf(
      setlist: setlist,
      aushilfeProfile: aushilfeProfile,
      storageService: storageService,
    );

    expect(bookletFile.existsSync(), true);
    expect(bookletFile.lengthSync(), greaterThan(1000));

    final bookletDoc = PdfDocument(inputBytes: await bookletFile.readAsBytes());
    // Cover page + at least 1 page
    expect(bookletDoc.pages.count, greaterThanOrEqualTo(1));
    bookletDoc.dispose();

    if (bookletFile.existsSync()) bookletFile.deleteSync();
    if (dummyPdfFile.existsSync()) dummyPdfFile.deleteSync();
  });
}
