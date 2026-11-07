import 'dart:io';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/musician_profile.dart';
import '../models/setlist.dart';
import '../models/song.dart';
import 'nextcloud_service.dart';
import 'storage_service.dart';
import 'voice_matcher.dart';

class SetlistPdfService {
  /// Generates a clean, professional A4 PDF overview (program / cue sheet)
  /// of the setlist with title, date, list of pieces, custom notes, and intermissions.
  static Future<File> generateSetlistOverviewPdf(Setlist setlist) async {
    final document = PdfDocument();
    document.pageSettings.size = PdfPageSize.a4;
    document.pageSettings.margins.all = 36; // 0.5 inch margins

    final page = document.pages.add();
    final pageWidth = page.getClientSize().width;
    final pageHeight = page.getClientSize().height;

    // Fonts
    final headerFont = PdfStandardFont(PdfFontFamily.helvetica, 22, style: PdfFontStyle.bold);
    final subheaderFont = PdfStandardFont(PdfFontFamily.helvetica, 12, style: PdfFontStyle.bold);
    final metaFont = PdfStandardFont(PdfFontFamily.helvetica, 10);
    final tableHeaderFont = PdfStandardFont(PdfFontFamily.helvetica, 10, style: PdfFontStyle.bold);
    final rowBoldFont = PdfStandardFont(PdfFontFamily.helvetica, 10, style: PdfFontStyle.bold);
    final rowRegularFont = PdfStandardFont(PdfFontFamily.helvetica, 9);
    final pauseFont = PdfStandardFont(PdfFontFamily.helvetica, 10, style: PdfFontStyle.bold);

    // Header Background Accent Bar
    page.graphics.drawRectangle(
      brush: PdfSolidBrush(PdfColor(67, 56, 202)), // Electric Indigo
      bounds: Rect.fromLTWH(0, 0, pageWidth, 54),
    );

    // Title inside header
    page.graphics.drawString(
      setlist.title,
      headerFont,
      brush: PdfBrushes.white,
      bounds: Rect.fromLTWH(14, 10, pageWidth - 28, 28),
      format: PdfStringFormat(lineAlignment: PdfVerticalAlignment.middle),
    );

    page.graphics.drawString(
      'Ablaufplan & Programm • Blasorchester 1862',
      metaFont,
      brush: PdfSolidBrush(PdfColor(224, 231, 255)),
      bounds: Rect.fromLTWH(14, 34, pageWidth - 28, 16),
    );

    // Meta row (Date, piece count)
    final dateStr = DateFormat('EEEE, dd. MMMM yyyy', 'de_DE').format(setlist.date);
    final playableCount = setlist.items.where((i) => !i.isIntermission).length;
    final pauseCount = setlist.items.where((i) => i.isIntermission).length;

    double yPos = 66;

    page.graphics.drawString(
      'Datum: $dateStr',
      subheaderFont,
      brush: PdfSolidBrush(PdfColor(30, 41, 59)),
      bounds: Rect.fromLTWH(0, yPos, pageWidth * 0.65, 18),
    );

    page.graphics.drawString(
      '$playableCount ${playableCount == 1 ? "Stück" : "Stücke"}${pauseCount > 0 ? " • $pauseCount Pause" : ""}',
      metaFont,
      brush: PdfSolidBrush(PdfColor(100, 116, 139)),
      bounds: Rect.fromLTWH(pageWidth * 0.65, yPos, pageWidth * 0.35, 18),
      format: PdfStringFormat(alignment: PdfTextAlignment.right),
    );

    yPos += 22;

    // Table of songs & intermissions
    final grid = PdfGrid();
    grid.columns.add(count: 3);
    grid.columns[0].width = 38;
    grid.columns[1].width = pageWidth - 38 - 140;
    grid.columns[2].width = 140;

    // Table Header
    final headerRow = grid.headers.add(1)[0];
    headerRow.cells[0].value = 'Nr.';
    headerRow.cells[1].value = 'Stück / Titel';
    headerRow.cells[2].value = 'Hinweise / Notizen';

    for (int i = 0; i < 3; i++) {
      headerRow.cells[i].style = PdfGridCellStyle(
        font: tableHeaderFont,
        backgroundBrush: PdfSolidBrush(PdfColor(241, 245, 249)),
        textBrush: PdfSolidBrush(PdfColor(71, 85, 105)),
        cellPadding: PdfPaddings(left: 6, right: 6, top: 6, bottom: 6),
      );
    }

    int songCounter = 1;
    for (final item in setlist.items) {
      final row = grid.rows.add();

      if (item.isIntermission) {
        row.cells[0].value = '-';
        row.cells[1].value = 'PAUSE / DURCHATMEN';
        row.cells[2].value = item.notes.isNotEmpty ? item.notes : '';

        for (int i = 0; i < 3; i++) {
          row.cells[i].style = PdfGridCellStyle(
            font: pauseFont,
            backgroundBrush: PdfSolidBrush(PdfColor(254, 243, 199)), // Amber light
            textBrush: PdfSolidBrush(PdfColor(180, 83, 9)), // Amber dark
            cellPadding: PdfPaddings(left: 6, right: 6, top: 6, bottom: 6),
          );
        }
      } else {
        row.cells[0].value = '$songCounter.';
        row.cells[1].value = item.songTitle;
        row.cells[2].value = item.notes;

        row.cells[0].style = PdfGridCellStyle(
          font: rowBoldFont,
          textBrush: PdfSolidBrush(PdfColor(100, 116, 139)),
          cellPadding: PdfPaddings(left: 6, right: 6, top: 6, bottom: 6),
        );
        row.cells[1].style = PdfGridCellStyle(
          font: rowBoldFont,
          textBrush: PdfSolidBrush(PdfColor(15, 23, 42)),
          cellPadding: PdfPaddings(left: 6, right: 6, top: 6, bottom: 6),
        );
        row.cells[2].style = PdfGridCellStyle(
          font: rowRegularFont,
          textBrush: PdfSolidBrush(PdfColor(79, 70, 229)),
          cellPadding: PdfPaddings(left: 6, right: 6, top: 6, bottom: 6),
        );

        songCounter++;
      }
    }

    grid.style = PdfGridStyle(
      cellPadding: PdfPaddings(left: 6, right: 6, top: 5, bottom: 5),
    );

    // Draw grid
    final gridResult = grid.draw(
      page: page,
      bounds: Rect.fromLTWH(0, yPos, pageWidth, pageHeight - yPos - 24),
    );

    // Footer on last page
    final lastPage = gridResult?.page ?? page;
    final footerY = pageHeight - 14;
    lastPage.graphics.drawString(
      'Erstellt mit Notencloud • ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}',
      PdfStandardFont(PdfFontFamily.helvetica, 8),
      brush: PdfSolidBrush(PdfColor(148, 163, 184)),
      bounds: Rect.fromLTWH(0, footerY, pageWidth, 14),
      format: PdfStringFormat(lineAlignment: PdfVerticalAlignment.bottom),
    );

    final bytes = await document.save();
    document.dispose();

    final tempDir = await getTemporaryDirectory();
    final safeTitle = setlist.title.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
    final file = File('${tempDir.path}/Setliste_$safeTitle.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Generates a complete, merged Sheet Music Booklet for a guest / substitute musician ("Aushilfe").
  /// Includes a custom Table of Contents on Page 1 (with start page numbers for each piece)
  /// followed immediately by the sheet music PDFs for the chosen instrument/voice.
  static Future<File> generateAushilfeBookletPdf({
    required Setlist setlist,
    required MusicianProfile aushilfeProfile,
    required StorageService storageService,
    NextcloudService? nextcloudService,
    void Function(int current, int total, String status)? onProgress,
  }) async {
    final allSongs = storageService.getCachedSongs();
    final mergedDoc = PdfDocument();

    // 1. First Pass: collect pieces, match voice parts, and ensure files are downloaded locally
    final totalItems = setlist.items.length;
    final playableCount = setlist.items.where((i) => !i.isIntermission).length;
    final List<_AushilfeItemInfo> collected = [];

    // Track page count in booklet (Cover page is Page 1)
    int currentBookletPage = 2;

    for (int i = 0; i < setlist.items.length; i++) {
      final item = setlist.items[i];
      onProgress?.call(i + 1, totalItems, 'Prüfe "${item.songTitle}"...');

      if (item.isIntermission) {
        collected.add(_AushilfeItemInfo(
          item: item,
          song: null,
          matchedPart: null,
          isFallback: false,
          startPage: null,
          pageCount: 0,
          localPdfPath: null,
        ));
        continue;
      }

      final song = allSongs.firstWhere(
        (s) => s.id == item.songId || s.folderName == item.songFolderName,
        orElse: () => Song(
          id: item.songId,
          title: item.songTitle,
          folderName: item.songFolderName,
          remoteFolderPath: '',
        ),
      );

      final match = VoiceMatcher.findDetailedMatchForSong(song, aushilfeProfile);
      final bestMatch = match?.part;
      final isFallback = match?.isFallback ?? false;

      String? localPdfPath;
      int piecePages = 0;

      if (bestMatch != null) {
        try {
          localPdfPath = await storageService.getLocalPdfPath(
            song.id,
            bestMatch.fileName,
            part: bestMatch,
          );
          final file = File(localPdfPath);
          if (!await file.exists() && nextcloudService != null) {
            onProgress?.call(i + 1, totalItems, 'Lade Noten für "${song.title}"...');
            await nextcloudService.downloadPart(bestMatch, localPdfPath);
          }

          if (await file.exists()) {
            final testDoc = PdfDocument(inputBytes: await file.readAsBytes());
            piecePages = testDoc.pages.count;
            testDoc.dispose();
          }
        } catch (_) {
          localPdfPath = null;
          piecePages = 0;
        }
      }

      final startPage = piecePages > 0 ? currentBookletPage : null;
      if (piecePages > 0) {
        currentBookletPage += piecePages;
      }

      collected.add(_AushilfeItemInfo(
        item: item,
        song: song,
        matchedPart: bestMatch,
        isFallback: isFallback,
        startPage: startPage,
        pageCount: piecePages,
        localPdfPath: localPdfPath,
      ));
    }

    // 2. Generate Cover / Table of Contents (Page 1)
    onProgress?.call(totalItems, totalItems, 'Erstelle Inhaltsverzeichnis...');
    final coverSection = mergedDoc.sections!.add();
    coverSection.pageSettings.size = PdfPageSize.a4;
    coverSection.pageSettings.margins.all = 36;
    final coverPage = coverSection.pages.add();
    final pageWidth = coverPage.getClientSize().width;
    final pageHeight = coverPage.getClientSize().height;

    // Header Background Accent Bar
    coverPage.graphics.drawRectangle(
      brush: PdfSolidBrush(PdfColor(16, 185, 129)), // Emerald accent for voice
      bounds: Rect.fromLTWH(0, 0, pageWidth, 62),
    );

    // Title inside header
    coverPage.graphics.drawString(
      'NOTENMAPPE • AUSHILFE',
      PdfStandardFont(PdfFontFamily.helvetica, 10, style: PdfFontStyle.bold),
      brush: PdfSolidBrush(PdfColor(209, 250, 229)),
      bounds: Rect.fromLTWH(14, 8, pageWidth - 28, 14),
    );

    coverPage.graphics.drawString(
      setlist.title,
      PdfStandardFont(PdfFontFamily.helvetica, 20, style: PdfFontStyle.bold),
      brush: PdfBrushes.white,
      bounds: Rect.fromLTWH(14, 22, pageWidth - 28, 24),
    );

    coverPage.graphics.drawString(
      'Stimme: ${aushilfeProfile.displayName}',
      PdfStandardFont(PdfFontFamily.helvetica, 11, style: PdfFontStyle.bold),
      brush: PdfBrushes.white,
      bounds: Rect.fromLTWH(14, 46, pageWidth - 28, 14),
    );

    // Subheader
    final dateStr = DateFormat('EEEE, dd. MMMM yyyy', 'de_DE').format(setlist.date);
    double yPos = 74;

    coverPage.graphics.drawString(
      'Konzertdatum: $dateStr',
      PdfStandardFont(PdfFontFamily.helvetica, 11, style: PdfFontStyle.bold),
      brush: PdfSolidBrush(PdfColor(30, 41, 59)),
      bounds: Rect.fromLTWH(0, yPos, pageWidth, 16),
    );

    yPos += 20;

    // Table of contents grid
    final grid = PdfGrid();
    grid.columns.add(count: 4);
    grid.columns[0].width = 30; // Nr.
    grid.columns[1].width = pageWidth - 30 - 150 - 50; // Titel
    grid.columns[2].width = 150; // Stimme / Notiz
    grid.columns[3].width = 50; // Seite

    final headerRow = grid.headers.add(1)[0];
    headerRow.cells[0].value = 'Nr.';
    headerRow.cells[1].value = 'Stück';
    headerRow.cells[2].value = 'Stimme / Notiz';
    headerRow.cells[3].value = 'Seite';

    for (int i = 0; i < 4; i++) {
      headerRow.cells[i].style = PdfGridCellStyle(
        font: PdfStandardFont(PdfFontFamily.helvetica, 9, style: PdfFontStyle.bold),
        backgroundBrush: PdfSolidBrush(PdfColor(241, 245, 249)),
        textBrush: PdfSolidBrush(PdfColor(71, 85, 105)),
        cellPadding: PdfPaddings(left: 4, right: 4, top: 5, bottom: 5),
      );
    }
    headerRow.cells[3].stringFormat = PdfStringFormat(alignment: PdfTextAlignment.right);

    int songCounter = 1;
    for (final info in collected) {
      final row = grid.rows.add();

      if (info.item.isIntermission) {
        row.cells[0].value = '-';
        row.cells[1].value = 'PAUSE / DURCHATMEN';
        row.cells[2].value = info.item.notes;
        row.cells[3].value = '-';

        for (int i = 0; i < 4; i++) {
          row.cells[i].style = PdfGridCellStyle(
            font: PdfStandardFont(PdfFontFamily.helvetica, 9, style: PdfFontStyle.bold),
            backgroundBrush: PdfSolidBrush(PdfColor(254, 243, 199)),
            textBrush: PdfSolidBrush(PdfColor(180, 83, 9)),
            cellPadding: PdfPaddings(left: 4, right: 4, top: 4, bottom: 4),
          );
        }
      } else {
        row.cells[0].value = '$songCounter.';
        row.cells[1].value = info.item.songTitle;

        final partLabel = info.matchedPart != null
            ? VoiceMatcher.getPartDisplayLabel(info.matchedPart!)
            : 'Keine Stimme gefunden';
        final notesSuffix = info.item.notes.isNotEmpty ? ' (${info.item.notes})' : '';
        row.cells[2].value = '$partLabel$notesSuffix';

        row.cells[3].value = info.startPage != null ? 'S. ${info.startPage}' : '-';

        row.cells[0].style = PdfGridCellStyle(
          font: PdfStandardFont(PdfFontFamily.helvetica, 9, style: PdfFontStyle.bold),
          textBrush: PdfSolidBrush(PdfColor(100, 116, 139)),
          cellPadding: PdfPaddings(left: 4, right: 4, top: 4, bottom: 4),
        );
        row.cells[1].style = PdfGridCellStyle(
          font: PdfStandardFont(PdfFontFamily.helvetica, 9, style: PdfFontStyle.bold),
          textBrush: PdfSolidBrush(PdfColor(15, 23, 42)),
          cellPadding: PdfPaddings(left: 4, right: 4, top: 4, bottom: 4),
        );
        row.cells[2].style = PdfGridCellStyle(
          font: PdfStandardFont(PdfFontFamily.helvetica, 8),
          textBrush: info.matchedPart == null
              ? PdfSolidBrush(PdfColor(225, 29, 72)) // Red if missing
              : (info.isFallback
                  ? PdfSolidBrush(PdfColor(217, 119, 6)) // Amber if fallback
                  : PdfSolidBrush(PdfColor(5, 150, 105))), // Green if exact
          cellPadding: PdfPaddings(left: 4, right: 4, top: 4, bottom: 4),
        );
        row.cells[3].style = PdfGridCellStyle(
          font: PdfStandardFont(PdfFontFamily.helvetica, 9, style: PdfFontStyle.bold),
          textBrush: PdfSolidBrush(PdfColor(79, 70, 229)),
          cellPadding: PdfPaddings(left: 4, right: 4, top: 4, bottom: 4),
        );
        row.cells[3].stringFormat = PdfStringFormat(alignment: PdfTextAlignment.right);

        songCounter++;
      }
    }

    grid.style = PdfGridStyle(cellPadding: PdfPaddings(left: 4, right: 4, top: 4, bottom: 4));
    grid.draw(page: coverPage, bounds: Rect.fromLTWH(0, yPos, pageWidth, pageHeight - yPos - 20));

    // Footer
    coverPage.graphics.drawString(
      'Notencloud • Blasorchester 1862 • Erstellt am ${DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now())}',
      PdfStandardFont(PdfFontFamily.helvetica, 8),
      brush: PdfSolidBrush(PdfColor(148, 163, 184)),
      bounds: Rect.fromLTWH(0, pageHeight - 14, pageWidth, 14),
      format: PdfStringFormat(lineAlignment: PdfVerticalAlignment.bottom),
    );

    // 3. Second Pass: append each sheet music piece PDF into mergedDoc
    int currentPieceNum = 0;
    for (final info in collected) {
      if (info.item.isIntermission || info.localPdfPath == null) continue;
      currentPieceNum++;
      onProgress?.call(currentPieceNum, playableCount, 'Füge "${info.item.songTitle}" hinzu...');

      final file = File(info.localPdfPath!);
      if (await file.exists()) {
        try {
          final inputDoc = PdfDocument(inputBytes: await file.readAsBytes());
          for (int p = 0; p < inputDoc.pages.count; p++) {
            final srcPage = inputDoc.pages[p];
            final section = mergedDoc.sections!.add();
            section.pageSettings.size = srcPage.size;
            section.pageSettings.margins.all = 0; // borderless to keep original scan

            final newPage = section.pages.add();
            final template = srcPage.createTemplate();
            newPage.graphics.drawPdfTemplate(template, const Offset(0, 0), srcPage.size);
          }
          inputDoc.dispose();
        } catch (_) {}
      }
    }

    onProgress?.call(playableCount, playableCount, 'Speichere Notenheft...');
    final bytes = await mergedDoc.save();
    mergedDoc.dispose();

    final tempDir = await getTemporaryDirectory();
    final safeTitle = setlist.title.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
    final safeVoice = aushilfeProfile.displayName.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
    final finalFile = File('${tempDir.path}/Notenheft_${safeTitle}_$safeVoice.pdf');
    await finalFile.writeAsBytes(bytes, flush: true);

    return finalFile;
  }
}

class _AushilfeItemInfo {
  final SetlistItem item;
  final Song? song;
  final PartFile? matchedPart;
  final bool isFallback;
  final int? startPage;
  final int pageCount;
  final String? localPdfPath;

  _AushilfeItemInfo({
    required this.item,
    required this.song,
    required this.matchedPart,
    required this.isFallback,
    required this.startPage,
    required this.pageCount,
    required this.localPdfPath,
  });
}
