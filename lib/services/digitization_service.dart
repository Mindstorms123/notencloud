import 'dart:io';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/song.dart';
import 'voice_matcher.dart';

enum AuditMode {
  standardBesetzung, // Standard Blasorchester (ca. 18 Kernstimmen)
  vollbesetzung,     // Großes Blasorchester (inkl. Klarinette 3, Horn 3-4, etc.)
  registerLuecken,   // Nur erkannte Lücken in bereits vorhandenen Registern
}

class StandardPartRequirement {
  final String instrument;
  final int voiceNumber; // 0 = kein Stimmen-Index nötig
  final String key;      // optional bevorzugte Stimmung
  final bool isCore;     // true = Standard-Besetzung, false = erweiterte Besetzung

  const StandardPartRequirement({
    required this.instrument,
    this.voiceNumber = 0,
    this.key = '',
    this.isCore = true,
  });

  String get displayName {
    final buffer = StringBuffer(instrument);
    if (voiceNumber > 0) buffer.write(' $voiceNumber');
    if (key.isNotEmpty) buffer.write(' ($key)');
    return buffer.toString();
  }
}

class SongDigitizationReport {
  final Song song;
  final List<String> presentParts;
  final List<String> missingParts;
  final int totalExpected;
  final int totalPresent;
  final double completionPercentage;

  const SongDigitizationReport({
    required this.song,
    required this.presentParts,
    required this.missingParts,
    required this.totalExpected,
    required this.totalPresent,
    required this.completionPercentage,
  });

  bool get isComplete => missingParts.isEmpty;
}

class DigitizationSummary {
  final int totalSongs;
  final int completeSongs;
  final int incompleteSongs;
  final int totalMissingParts;
  final double overallPercentage;
  final Map<String, int> missingByInstrument;

  const DigitizationSummary({
    required this.totalSongs,
    required this.completeSongs,
    required this.incompleteSongs,
    required this.totalMissingParts,
    required this.overallPercentage,
    required this.missingByInstrument,
  });
}

class DigitizationService {
  // Standard Blasorchester Part Requirements
  static const List<StandardPartRequirement> standardRequirements = [
    // Flöten
    StandardPartRequirement(instrument: 'Flöte', voiceNumber: 1, key: 'C', isCore: true),
    StandardPartRequirement(instrument: 'Flöte', voiceNumber: 2, key: 'C', isCore: true),
    StandardPartRequirement(instrument: 'Piccoloflöte', voiceNumber: 0, isCore: false),
    StandardPartRequirement(instrument: 'Oboe', voiceNumber: 0, isCore: false),
    StandardPartRequirement(instrument: 'Fagott', voiceNumber: 0, isCore: false),

    // Klarinetten
    StandardPartRequirement(instrument: 'Es-Klarinette', voiceNumber: 0, isCore: false),
    StandardPartRequirement(instrument: 'Klarinette', voiceNumber: 1, key: 'Bb', isCore: true),
    StandardPartRequirement(instrument: 'Klarinette', voiceNumber: 2, key: 'Bb', isCore: true),
    StandardPartRequirement(instrument: 'Klarinette', voiceNumber: 3, key: 'Bb', isCore: false),
    StandardPartRequirement(instrument: 'Bassklarinette', voiceNumber: 0, isCore: false),

    // Saxophone
    StandardPartRequirement(instrument: 'Altsaxophon', voiceNumber: 1, key: 'Eb', isCore: true),
    StandardPartRequirement(instrument: 'Altsaxophon', voiceNumber: 2, key: 'Eb', isCore: true),
    StandardPartRequirement(instrument: 'Tenorsaxophon', voiceNumber: 1, key: 'Bb', isCore: true),
    StandardPartRequirement(instrument: 'Baritonsaxophon', voiceNumber: 0, key: 'Eb', isCore: false),

    // Hohes Blech
    StandardPartRequirement(instrument: 'Flügelhorn', voiceNumber: 1, key: 'Bb', isCore: true),
    StandardPartRequirement(instrument: 'Flügelhorn', voiceNumber: 2, key: 'Bb', isCore: false),
    StandardPartRequirement(instrument: 'Trompete', voiceNumber: 1, key: 'Bb', isCore: true),
    StandardPartRequirement(instrument: 'Trompete', voiceNumber: 2, key: 'Bb', isCore: true),
    StandardPartRequirement(instrument: 'Trompete', voiceNumber: 3, key: 'Bb', isCore: false),

    // Hörner
    StandardPartRequirement(instrument: 'Waldhorn', voiceNumber: 1, key: 'F', isCore: true),
    StandardPartRequirement(instrument: 'Waldhorn', voiceNumber: 2, key: 'F', isCore: true),
    StandardPartRequirement(instrument: 'Waldhorn', voiceNumber: 3, key: 'F', isCore: false),
    StandardPartRequirement(instrument: 'Waldhorn', voiceNumber: 4, key: 'F', isCore: false),

    // Tiefes Blech
    StandardPartRequirement(instrument: 'Tenorhorn', voiceNumber: 1, key: 'Bb', isCore: true),
    StandardPartRequirement(instrument: 'Bariton', voiceNumber: 0, key: 'C', isCore: true),
    StandardPartRequirement(instrument: 'Posaune', voiceNumber: 1, key: 'C', isCore: true),
    StandardPartRequirement(instrument: 'Posaune', voiceNumber: 2, key: 'C', isCore: true),
    StandardPartRequirement(instrument: 'Posaune', voiceNumber: 3, key: 'C', isCore: false),
    StandardPartRequirement(instrument: 'Tuba', voiceNumber: 1, key: 'C', isCore: true),
    StandardPartRequirement(instrument: 'Tuba', voiceNumber: 2, key: 'C', isCore: false),

    // Rhythmus & Leitung
    StandardPartRequirement(instrument: 'Percussion', voiceNumber: 0, isCore: true),
    StandardPartRequirement(instrument: 'Partitur', voiceNumber: 0, isCore: true),
  ];

  /// Analyzes a single song and identifies missing parts and voice gaps
  static SongDigitizationReport analyzeSong(
    Song song, {
    AuditMode mode = AuditMode.standardBesetzung,
  }) {
    if (song.isDocumentOrList) {
      return SongDigitizationReport(
        song: song,
        presentParts: song.parts.map((p) => p.fileName).toList(),
        missingParts: const [],
        totalExpected: song.parts.length,
        totalPresent: song.parts.length,
        completionPercentage: 100.0,
      );
    }

    final presentList = <String>[];
    final missingSet = <String>{};

    for (final p in song.parts) {
      presentList.add(VoiceMatcher.getPartDisplayLabel(p));
    }

    // 1. Detect internal gaps in existing instrument sections
    // (e.g. if Trompete 1 and 3 are present, Trompete 2 is a guaranteed gap!)
    final instrumentMaxVoices = <String, int>{};
    final instrumentPresentVoices = <String, Set<int>>{};

    for (final p in song.parts) {
      final inst = p.detectedInstrument;
      if (inst == 'Zusatzstimme' || inst == 'Partitur' || inst == 'Direktion') continue;

      final currentMax = instrumentMaxVoices[inst] ?? 0;
      if (p.detectedVoice > currentMax) {
        instrumentMaxVoices[inst] = p.detectedVoice;
      }

      final voiceSet = instrumentPresentVoices.putIfAbsent(inst, () => <int>{});
      if (p.detectedVoice > 0) {
        voiceSet.add(p.detectedVoice);
        if (p.isCombinedVoice) {
          if (p.detectedVoice == 1) voiceSet.add(2);
          if (p.detectedVoice == 3) voiceSet.add(4);
        }
      }
    }

    // Identify gaps
    instrumentMaxVoices.forEach((inst, maxV) {
      if (maxV > 1) {
        final present = instrumentPresentVoices[inst] ?? {};
        for (int v = 1; v <= maxV; v++) {
          if (!present.contains(v)) {
            missingSet.add('$inst $v');
          }
        }
      }
    });

    // 2. If mode includes standard requirements, check against requirements
    if (mode != AuditMode.registerLuecken) {
      final requirements = mode == AuditMode.vollbesetzung
          ? standardRequirements
          : standardRequirements.where((r) => r.isCore).toList();

      for (final req in requirements) {
        bool isCovered = false;

        for (final p in song.parts) {
          if (p.detectedInstrument.toLowerCase() == req.instrument.toLowerCase()) {
            if (req.voiceNumber == 0) {
              isCovered = true;
              break;
            } else if (p.detectedVoice == req.voiceNumber) {
              isCovered = true;
              break;
            } else if (p.isCombinedVoice) {
              if (p.detectedVoice == 1 && (req.voiceNumber == 1 || req.voiceNumber == 2)) {
                isCovered = true;
                break;
              }
              if (p.detectedVoice == 3 && (req.voiceNumber == 3 || req.voiceNumber == 4)) {
                isCovered = true;
                break;
              }
            }
          }
        }

        if (!isCovered) {
          missingSet.add(req.displayName);
        }
      }
    }

    final missingList = missingSet.toList()..sort();
    final expectedCount = presentList.length + missingList.length;
    final percent = expectedCount > 0
        ? ((presentList.length / expectedCount) * 100.0).clamp(0.0, 100.0)
        : 100.0;

    return SongDigitizationReport(
      song: song,
      presentParts: presentList,
      missingParts: missingList,
      totalExpected: expectedCount,
      totalPresent: presentList.length,
      completionPercentage: percent,
    );
  }

  /// Analyzes a full repertoire list of songs
  static List<SongDigitizationReport> analyzeAllSongs(
    List<Song> songs, {
    AuditMode mode = AuditMode.standardBesetzung,
  }) {
    return songs
        .where((s) => !s.isDocumentOrList)
        .map((s) => analyzeSong(s, mode: mode))
        .toList();
  }

  /// Calculates statistical summary across all analyzed song reports
  static DigitizationSummary calculateSummary(List<SongDigitizationReport> reports) {
    if (reports.isEmpty) {
      return const DigitizationSummary(
        totalSongs: 0,
        completeSongs: 0,
        incompleteSongs: 0,
        totalMissingParts: 0,
        overallPercentage: 100.0,
        missingByInstrument: {},
      );
    }

    int completeCount = 0;
    int incompleteCount = 0;
    int missingTotal = 0;
    int presentTotal = 0;
    final missingMap = <String, int>{};

    for (final r in reports) {
      if (r.isComplete) {
        completeCount++;
      } else {
        incompleteCount++;
      }
      missingTotal += r.missingParts.length;
      presentTotal += r.totalPresent;

      for (final m in r.missingParts) {
        missingMap[m] = (missingMap[m] ?? 0) + 1;
      }
    }

    final sortedMissingMap = Map.fromEntries(
      missingMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );

    final totalParts = presentTotal + missingTotal;
    final overallPct = totalParts > 0 ? (presentTotal / totalParts) * 100.0 : 100.0;

    return DigitizationSummary(
      totalSongs: reports.length,
      completeSongs: completeCount,
      incompleteSongs: incompleteCount,
      totalMissingParts: missingTotal,
      overallPercentage: overallPct,
      missingByInstrument: sortedMissingMap,
    );
  }

  /// Formats a clean, readable text message suitable for WhatsApp, email or messaging
  static String generateShareText(
    List<SongDigitizationReport> reports, {
    String? categoryFilter,
    String? instrumentFilter,
  }) {
    final filtered = reports.where((r) {
      if (categoryFilter != null && categoryFilter.isNotEmpty && categoryFilter != 'Alle Kategorien') {
        if (r.song.category != categoryFilter) return false;
      }
      if (instrumentFilter != null && instrumentFilter.isNotEmpty && instrumentFilter != 'Alle Instrumente') {
        final matches = r.missingParts.any((m) => m.toLowerCase().contains(instrumentFilter.toLowerCase()));
        if (!matches) return false;
      }
      return !r.isComplete;
    }).toList();

    final buffer = StringBuffer();
    final dateStr = DateFormat('dd.MM.yyyy').format(DateTime.now());

    buffer.writeln('📋 *Notencloud - Fehlende Noten zum Digitalisieren*');
    buffer.writeln('Stand: $dateStr • ${filtered.length} unvollständige Stücke\n');

    if (categoryFilter != null && categoryFilter.isNotEmpty && categoryFilter != 'Alle Kategorien') {
      buffer.writeln('Kategorie: $categoryFilter\n');
    }

    if (instrumentFilter != null && instrumentFilter.isNotEmpty && instrumentFilter != 'Alle Instrumente') {
      buffer.writeln('Gefiltert nach: $instrumentFilter\n');
    }

    int index = 1;
    for (final r in filtered) {
      buffer.writeln('$index. *${r.song.title}* (${r.completionPercentage.round()}% vorhanden)');
      final relevantMissing = (instrumentFilter != null && instrumentFilter.isNotEmpty && instrumentFilter != 'Alle Instrumente')
          ? r.missingParts.where((m) => m.toLowerCase().contains(instrumentFilter.toLowerCase())).toList()
          : r.missingParts;
      buffer.writeln('   ❌ Fehlt: ${relevantMissing.join(', ')}');
      index++;
    }

    return buffer.toString();
  }

  /// Generates a clean A4 PDF table listing missing parts per song for the music librarian
  static Future<File> generateAuditPdf(
    List<SongDigitizationReport> reports, {
    String? categoryFilter,
    String? instrumentFilter,
    String orchestraName = 'Blasorchester 1862',
  }) async {
    final filtered = reports.where((r) {
      if (categoryFilter != null && categoryFilter.isNotEmpty && categoryFilter != 'Alle Kategorien') {
        if (r.song.category != categoryFilter) return false;
      }
      if (instrumentFilter != null && instrumentFilter.isNotEmpty && instrumentFilter != 'Alle Instrumente') {
        final matches = r.missingParts.any((m) => m.toLowerCase().contains(instrumentFilter.toLowerCase()));
        if (!matches) return false;
      }
      return !r.isComplete;
    }).toList();

    final document = PdfDocument();
    document.pageSettings.size = PdfPageSize.a4;
    document.pageSettings.margins.all = 36; // 0.5 in margins

    PdfPage page = document.pages.add();
    final pageWidth = page.getClientSize().width;
    final pageHeight = page.getClientSize().height;

    // Fonts
    final titleFont = PdfStandardFont(PdfFontFamily.helvetica, 18, style: PdfFontStyle.bold);
    final subtitleFont = PdfStandardFont(PdfFontFamily.helvetica, 10);
    final headerFont = PdfStandardFont(PdfFontFamily.helvetica, 10, style: PdfFontStyle.bold);
    final regularFont = PdfStandardFont(PdfFontFamily.helvetica, 9);
    final boldFont = PdfStandardFont(PdfFontFamily.helvetica, 9, style: PdfFontStyle.bold);
    final smallFont = PdfStandardFont(PdfFontFamily.helvetica, 8);

    // Header bar
    page.graphics.drawRectangle(
      brush: PdfSolidBrush(PdfColor(67, 56, 202)), // Electric Indigo
      bounds: Rect.fromLTWH(0, 0, pageWidth, 52),
    );

    page.graphics.drawString(
      'Digitalisierungs-Bedarf & Fehlende Noten',
      titleFont,
      brush: PdfBrushes.white,
      bounds: Rect.fromLTWH(14, 8, pageWidth - 28, 24),
    );

    final dateStr = DateFormat('dd.MM.yyyy').format(DateTime.now());
    page.graphics.drawString(
      '$orchestraName • Stand: $dateStr • ${filtered.length} unvollständige Stücke',
      subtitleFont,
      brush: PdfSolidBrush(PdfColor(224, 231, 255)),
      bounds: Rect.fromLTWH(14, 32, pageWidth - 28, 16),
    );

    double currentY = 66;

    // Table Header
    page.graphics.drawRectangle(
      brush: PdfSolidBrush(PdfColor(241, 245, 249)),
      bounds: Rect.fromLTWH(0, currentY, pageWidth, 20),
    );
    page.graphics.drawString('#', headerFont, brush: PdfSolidBrush(PdfColor(71, 85, 105)), bounds: Rect.fromLTWH(6, currentY + 4, 20, 16));
    page.graphics.drawString('Stück / Titel', headerFont, brush: PdfSolidBrush(PdfColor(71, 85, 105)), bounds: Rect.fromLTWH(30, currentY + 4, 160, 16));
    page.graphics.drawString('Kategorie', headerFont, brush: PdfSolidBrush(PdfColor(71, 85, 105)), bounds: Rect.fromLTWH(195, currentY + 4, 95, 16));
    page.graphics.drawString('Fehlende Stimmen (noch zu digitalisieren)', headerFont, brush: PdfSolidBrush(PdfColor(71, 85, 105)), bounds: Rect.fromLTWH(295, currentY + 4, pageWidth - 300, 16));
    currentY += 24;

    int itemIndex = 1;
    for (final r in filtered) {
      final relevantMissing = (instrumentFilter != null && instrumentFilter.isNotEmpty && instrumentFilter != 'Alle Instrumente')
          ? r.missingParts.where((m) => m.toLowerCase().contains(instrumentFilter.toLowerCase())).toList()
          : r.missingParts;

      final missingStr = relevantMissing.join(', ');
      final titleStr = r.song.title;
      final catStr = r.song.category;

      // Calculate row height based on text length
      final textHeight = (missingStr.length > 55 ? 32.0 : 20.0);

      // Check page break
      if (currentY + textHeight > pageHeight - 30) {
        page = document.pages.add();
        currentY = 20;

        // Draw subheader on new page
        page.graphics.drawRectangle(
          brush: PdfSolidBrush(PdfColor(241, 245, 249)),
          bounds: Rect.fromLTWH(0, currentY, pageWidth, 20),
        );
        page.graphics.drawString('#', headerFont, brush: PdfSolidBrush(PdfColor(71, 85, 105)), bounds: Rect.fromLTWH(6, currentY + 4, 20, 16));
        page.graphics.drawString('Stück / Titel', headerFont, brush: PdfSolidBrush(PdfColor(71, 85, 105)), bounds: Rect.fromLTWH(30, currentY + 4, 160, 16));
        page.graphics.drawString('Kategorie', headerFont, brush: PdfSolidBrush(PdfColor(71, 85, 105)), bounds: Rect.fromLTWH(195, currentY + 4, 95, 16));
        page.graphics.drawString('Fehlende Stimmen (noch zu digitalisieren)', headerFont, brush: PdfSolidBrush(PdfColor(71, 85, 105)), bounds: Rect.fromLTWH(295, currentY + 4, pageWidth - 300, 16));
        currentY += 24;
      }

      // Alternate row backgrounds
      if (itemIndex % 2 == 0) {
        page.graphics.drawRectangle(
          brush: PdfSolidBrush(PdfColor(248, 250, 252)),
          bounds: Rect.fromLTWH(0, currentY, pageWidth, textHeight),
        );
      }

      // Row separator
      page.graphics.drawLine(
        PdfPen(PdfColor(226, 232, 240), width: 0.5),
        Offset(0, currentY + textHeight),
        Offset(pageWidth, currentY + textHeight),
      );

      // Index
      page.graphics.drawString('$itemIndex', regularFont, brush: PdfSolidBrush(PdfColor(100, 116, 139)), bounds: Rect.fromLTWH(6, currentY + 3, 20, 16));

      // Title & Progress
      page.graphics.drawString(titleStr, boldFont, bounds: Rect.fromLTWH(30, currentY + 2, 160, 14));
      page.graphics.drawString('${r.completionPercentage.round()}% vorhanden (${r.totalPresent} Stimmen)', smallFont, brush: PdfSolidBrush(PdfColor(148, 163, 184)), bounds: Rect.fromLTWH(30, currentY + 16, 160, 12));

      // Category
      page.graphics.drawString(catStr, regularFont, brush: PdfSolidBrush(PdfColor(71, 85, 105)), bounds: Rect.fromLTWH(195, currentY + 3, 95, 16));

      // Missing parts (in red font)
      page.graphics.drawString(
        missingStr,
        boldFont,
        brush: PdfSolidBrush(PdfColor(225, 29, 72)), // Rose Red
        bounds: Rect.fromLTWH(295, currentY + 3, pageWidth - 300, textHeight - 4),
        format: PdfStringFormat(lineAlignment: PdfVerticalAlignment.top),
      );

      currentY += textHeight + 4;
      itemIndex++;
    }

    // Save to temp file
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/Fehlende_Noten_Digitalisierung_$dateStr.pdf');
    final bytes = await document.save();
    document.dispose();

    await file.writeAsBytes(bytes);
    return file;
  }
}
