// Messung/Prüfung des Notenhefts im Browser. Aufruf:
//   (cd build/web && python3 <Server mit CORS> 8794) &
//   CHROME_EXECUTABLE=/usr/bin/google-chrome flutter test --platform chrome test/perf/booklet_web_perf_test.dart
@TestOn('browser')
library;

import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:notencloud/models/musician_profile.dart';
import 'package:notencloud/models/setlist.dart';
import 'package:notencloud/models/song.dart';
import 'package:notencloud/services/setlist_pdf_service.dart';
import 'package:notencloud/services/storage_service.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

Future<Uint8List> scanPng(int seed) async {
  const w = 620, h = 877;
  final rnd = Random(seed);
  final px = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    // Papier mit Rauschen und dunklen "Noten"-Streifen
    final line = (i ~/ w) % 40 < 3;
    final v = line ? 20 + rnd.nextInt(40) : 215 + rnd.nextInt(40);
    px[i * 4] = v;
    px[i * 4 + 1] = v;
    px[i * 4 + 2] = v;
    px[i * 4 + 3] = 255;
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(px);
  final desc = ui.ImageDescriptor.raw(buffer, width: w, height: h, pixelFormat: ui.PixelFormat.rgba8888);
  final codec = await desc.instantiateCodec();
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

void main() {
  test('booklet of 16 scanned pieces', () async {
    // Die Testumgebung liefert die PDFium-Dateien nicht aus: lokaler Server mit build/web.
    pdfrx.Pdfrx.pdfiumWasmModulesUrl = 'http://127.0.0.1:8794/assets/packages/pdfrx/assets/';
    await initializeDateFormatting('de_DE');
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();

    final sw = Stopwatch()..start();
    final png = await scanPng(1);
    print('PNG ${png.length ~/ 1024} KB in ${sw.elapsedMilliseconds} ms');

    final songs = <Song>[];
    final items = <SetlistItem>[];
    // Gestochene Noten: viele Vektorlinien und Text je Seite statt eines Scans.
    final doc = PdfDocument();
    final rnd = Random(7);
    final pen = PdfPen(PdfColor(0, 0, 0), width: 0.4);
    final font = PdfStandardFont(PdfFontFamily.helvetica, 6);
    for (var p = 0; p < 3; p++) {
      final g = doc.pages.add().graphics;
      for (var n = 0; n < 12000; n++) {
        final x = rnd.nextDouble() * 500, y = rnd.nextDouble() * 750;
        g.drawLine(pen, ui.Offset(x, y), ui.Offset(x + rnd.nextDouble() * 8, y + rnd.nextDouble() * 8));
        if (n % 20 == 0) g.drawString('${n % 97}', font, bounds: ui.Rect.fromLTWH(x, y, 20, 8));
      }
    }
    final bytes = Uint8List.fromList(await doc.save());
    doc.dispose();
    print('Stück-PDF ${bytes.length ~/ 1024} KB nach ${sw.elapsedMilliseconds} ms');
    for (var i = 0; i < 16; i++) {
      final song = Song(
        id: 'song_$i',
        title: 'Stück $i',
        folderName: 'Stück $i',
        remoteFolderPath: '/Noten/Stück $i',
        parts: [
          PartFile(
            id: 'p$i',
            songId: 'song_$i',
            fileName: 'Trompete 2.pdf',
            remotePath: '/Noten/Stück $i/Trompete 2.pdf',
            detectedInstrument: 'Trompete',
            detectedVoice: 2,
            detectedKey: 'Bb',
          ),
        ],
      );
      songs.add(song);
      storage.cachePartBytes(song.id, 'Trompete 2.pdf', bytes);
      items.add(SetlistItem(id: 'i$i', songId: song.id, songTitle: song.title, songFolderName: song.folderName, order: i));
    }
    await storage.saveCachedSongs(songs);
    print('Vorbereitung ${sw.elapsedMilliseconds} ms');

    sw.reset();
    final pdf = await SetlistPdfService.buildAushilfeBookletPdf(
      setlist: Setlist.create(title: 'Gala', items: items),
      aushilfeProfile: const MusicianProfile(instrument: 'Trompete', voiceNumber: 2, keyOrClef: 'Bb'),
      storageService: storage,
    );
    print('Notenheft in ${sw.elapsedMilliseconds} ms, ${pdf.bytes.length ~/ 1024} KB');
    final check = PdfDocument(inputBytes: pdf.bytes);
    expect(check.pages.count, 49);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
