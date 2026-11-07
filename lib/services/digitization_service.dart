import 'dart:io';
import 'dart:ui';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../models/song.dart';
import 'voice_matcher.dart';

enum AuditMode {
  smartBesetzung,    // Auto-Erkennung (Pop/Rock/Concert Band ohne Flügelhorn vs. Traditionell Blasorchester)
  standardBesetzung, // Klassische Kernbesetzung (stur alle ~18 Kernstimmen)
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
  final List<String> ignoredParts;
  final int totalExpected;
  final int totalPresent;
  final double completionPercentage;

  const SongDigitizationReport({
    required this.song,
    required this.presentParts,
    required this.missingParts,
    this.ignoredParts = const [],
    required this.totalExpected,
    required this.totalPresent,
    required this.completionPercentage,
  });

  bool get isComplete => missingParts.isEmpty;
}

class DigitizationPriority {
  final String instrumentOrVoice; // e.g. "Trompete 2" or "Flügelhorn 1"
  final int missingCount;          // e.g. 14 pieces missing this voice
  final int presentCount;          // e.g. 6 pieces have it
  final int totalEligibleSongs;    // e.g. 20 pieces
  final double completionRate;     // e.g. 30.0%
  final List<Song> songsMissing;   // Song objects missing this part

  const DigitizationPriority({
    required this.instrumentOrVoice,
    required this.missingCount,
    required this.presentCount,
    required this.totalEligibleSongs,
    required this.completionRate,
    required this.songsMissing,
  });
}

class DigitizationSummary {
  final int totalSongs;
  final int completeSongs;
  final int incompleteSongs;
  final int totalMissingParts;
  final double overallPercentage;
  final Map<String, int> missingByInstrument;
  final List<DigitizationPriority> priorities;

  const DigitizationSummary({
    required this.totalSongs,
    required this.completeSongs,
    required this.incompleteSongs,
    required this.totalMissingParts,
    required this.overallPercentage,
    required this.missingByInstrument,
    this.priorities = const [],
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

  /// Checks if an instrument in the part satisfies a standard requirement
  static bool areInstrumentsCompatible(String partInstrument, String requiredInstrument) {
    final p = partInstrument.toLowerCase();
    final r = requiredInstrument.toLowerCase();
    if (p == r) return true;

    // Kornett / Cornet satisfies Trompete
    if ((p == 'kornett' || p == 'cornet') && r == 'trompete') return true;
    if (p == 'trompete' && (r == 'kornett' || r == 'cornet')) return true;

    // Euphonium satisfies Bariton / Tenorhorn
    if (p == 'euphonium' && (r == 'bariton' || r == 'tenorhorn')) return true;
    if ((p == 'bariton' || p == 'tenorhorn') && r == 'euphonium') return true;

    // Bariton and Tenorhorn satisfy each other in Blasorchester arrangements
    if (p == 'bariton' && r == 'tenorhorn') return true;
    if (p == 'tenorhorn' && r == 'bariton') return true;

    return false;
  }

  /// Checks whether a song is expected to have Flügelhorn parts
  static bool isFluegelhornExpectedForSong(Song song) {
    // 1. If any Flügelhorn part is already present, it is definitely expected!
    final hasFluegel = song.parts.any((p) =>
        p.detectedInstrument.toLowerCase() == 'flügelhorn' ||
        p.fileName.toLowerCase().contains('fluegel') ||
        p.fileName.toLowerCase().contains('flügel'));
    if (hasFluegel) return true;

    // 2. If it has traditional Tenorhorn parts, it's a traditional German Blasorchester piece
    final hasTenorhorn = song.parts.any((p) =>
        p.detectedInstrument.toLowerCase() == 'tenorhorn' ||
        p.fileName.toLowerCase().contains('tenorhorn'));
    if (hasTenorhorn) return true;

    // 3. Category checks for traditional pieces
    final cat = song.category.toLowerCase();
    if (cat.contains('polka') ||
        cat.contains('marsch') ||
        cat.contains('walzer') ||
        cat.contains('böhmisch') ||
        cat.contains('traditionell') ||
        cat.contains('volksmusik')) {
      return true;
    }

    // 4. Modern categories definitely don't have Flügelhorn in their original editions
    if (cat.contains('rock') ||
        cat.contains('pop') ||
        cat.contains('modern') ||
        cat.contains('film') ||
        cat.contains('musical') ||
        cat.contains('big band') ||
        cat.contains('swing') ||
        cat.contains('jazz') ||
        cat.contains('disney')) {
      return false;
    }

    // 5. Look at trumpet parts: if piece has 3 or more trumpet parts, it's a concert band setting
    int trumpetCount = 0;
    for (final p in song.parts) {
      if (p.detectedInstrument.toLowerCase() == 'trompete' ||
          p.fileName.toLowerCase().contains('trumpet') ||
          p.fileName.toLowerCase().contains('cornet')) {
        trumpetCount++;
      }
    }
    if (trumpetCount >= 3) {
      return false;
    }

    // If no flügelhorn and no tenorhorn parts are in the folder, and it has trumpet parts,
    // default to not requiring flügelhorn in smart mode
    return false;
  }

  /// Checks whether a song is expected to have German Tenorhorn parts
  static bool isTenorhornExpectedForSong(Song song) {
    // 1. If Tenorhorn is already present, it is definitely expected
    final hasTenorhorn = song.parts.any((p) =>
        p.detectedInstrument.toLowerCase() == 'tenorhorn' ||
        p.fileName.toLowerCase().contains('tenorhorn'));
    if (hasTenorhorn) return true;

    // 2. Traditional categories
    final cat = song.category.toLowerCase();
    if (cat.contains('polka') ||
        cat.contains('marsch') ||
        cat.contains('walzer') ||
        cat.contains('böhmisch') ||
        cat.contains('traditionell')) {
      return true;
    }

    // 3. Modern concert band pieces use Euphonium / Baritone instead of German Tenorhorn
    final hasBaritoneOrEuph = song.parts.any((p) =>
        p.detectedInstrument.toLowerCase() == 'bariton' ||
        p.detectedInstrument.toLowerCase() == 'euphonium' ||
        p.fileName.toLowerCase().contains('euphonium') ||
        p.fileName.toLowerCase().contains('baritone'));
    if (hasBaritoneOrEuph) {
      return false;
    }

    return false;
  }

  /// Analyzes a single song and identifies missing parts and voice gaps
  static SongDigitizationReport analyzeSong(
    Song song, {
    AuditMode mode = AuditMode.smartBesetzung,
    List<String> ignoredParts = const [],
  }) {
    if (song.isDocumentOrList) {
      return SongDigitizationReport(
        song: song,
        presentParts: song.parts.map((p) => p.fileName).toList(),
        missingParts: const [],
        ignoredParts: ignoredParts,
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
    final instrumentHasUnnumbered = <String, bool>{};

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
      } else {
        instrumentHasUnnumbered[inst] = true;
      }
    }

    // In music publishing, an unnumbered part (e.g. "Bariton.pdf") alongside a numbered part
    // (e.g. "Bariton 2.pdf") represents the 1st voice (Voice 1)!
    instrumentHasUnnumbered.forEach((inst, hasZero) {
      if (hasZero) {
        final voiceSet = instrumentPresentVoices.putIfAbsent(inst, () => <int>{});
        if (!voiceSet.contains(1)) {
          voiceSet.add(1);
        }
      }
    });

    // Cross-satisfaction for equivalent low brass instruments (Bariton / Euphonium / Tenorhorn)
    final hasLowBrass1 = (instrumentPresentVoices['Bariton']?.contains(1) ?? false) ||
        (instrumentPresentVoices['Euphonium']?.contains(1) ?? false) ||
        (instrumentPresentVoices['Tenorhorn']?.contains(1) ?? false);
    if (hasLowBrass1) {
      instrumentPresentVoices.putIfAbsent('Bariton', () => <int>{}).add(1);
      instrumentPresentVoices.putIfAbsent('Tenorhorn', () => <int>{}).add(1);
      instrumentPresentVoices.putIfAbsent('Euphonium', () => <int>{}).add(1);
    }

    final hasLowBrass2 = (instrumentPresentVoices['Bariton']?.contains(2) ?? false) ||
        (instrumentPresentVoices['Euphonium']?.contains(2) ?? false) ||
        (instrumentPresentVoices['Tenorhorn']?.contains(2) ?? false);
    if (hasLowBrass2) {
      instrumentPresentVoices.putIfAbsent('Bariton', () => <int>{}).add(2);
      instrumentPresentVoices.putIfAbsent('Tenorhorn', () => <int>{}).add(2);
      instrumentPresentVoices.putIfAbsent('Euphonium', () => <int>{}).add(2);
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
        // Smart mode exclusions for non-existent instruments in modern literature
        if (mode == AuditMode.smartBesetzung) {
          if (req.instrument == 'Flügelhorn' && !isFluegelhornExpectedForSong(song)) {
            continue;
          }
          if (req.instrument == 'Tenorhorn' && !isTenorhornExpectedForSong(song)) {
            continue;
          }
        }

        bool isCovered = false;

        for (final p in song.parts) {
          if (areInstrumentsCompatible(p.detectedInstrument, req.instrument)) {
            if (req.voiceNumber == 0) {
              isCovered = true;
              break;
            } else if (p.detectedVoice == req.voiceNumber) {
              isCovered = true;
              break;
            } else if (req.voiceNumber == 1 && p.detectedVoice == 0) {
              // An unnumbered part (e.g. "Bariton in C.pdf" or "Trompete in Bb.pdf") satisfies voice 1!
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

    // Remove parts marked as "nicht im Original vorhanden"
    if (ignoredParts.isNotEmpty) {
      missingSet.removeWhere((m) {
        return ignoredParts.any((ignored) =>
            m.toLowerCase().contains(ignored.toLowerCase()) ||
            ignored.toLowerCase().contains(m.toLowerCase()));
      });
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
      ignoredParts: ignoredParts,
      totalExpected: expectedCount,
      totalPresent: presentList.length,
      completionPercentage: percent,
    );
  }

  /// Analyzes a full repertoire list of songs
  static List<SongDigitizationReport> analyzeAllSongs(
    List<Song> songs, {
    AuditMode mode = AuditMode.smartBesetzung,
    Map<String, List<String>> ignoredPartsMap = const {},
  }) {
    return songs
        .where((s) => !s.isDocumentOrList)
        .map((s) => analyzeSong(
              s,
              mode: mode,
              ignoredParts: ignoredPartsMap[s.id] ?? const [],
            ))
        .toList();
  }

  /// Calculates prioritized recommendations for what voices/instruments to digitize next
  /// to achieve the fastest and highest impact on the overall repertoire completeness.
  static List<DigitizationPriority> calculatePriorities(
    List<SongDigitizationReport> reports, {
    int maxResults = 5,
  }) {
    if (reports.isEmpty) return const [];

    final missingMap = <String, List<SongDigitizationReport>>{};
    final presentMap = <String, int>{};

    for (final r in reports) {
      for (final m in r.missingParts) {
        missingMap.putIfAbsent(m, () => []).add(r);
      }
      for (final p in r.presentParts) {
        presentMap[p] = (presentMap[p] ?? 0) + 1;
      }
    }

    final priorities = <DigitizationPriority>[];

    missingMap.forEach((partName, missingReports) {
      final missingCount = missingReports.length;
      int presentCount = 0;
      presentMap.forEach((pName, count) {
        if (pName.toLowerCase().contains(partName.toLowerCase()) ||
            partName.toLowerCase().contains(pName.toLowerCase())) {
          presentCount += count;
        }
      });

      final total = presentCount + missingCount;
      final rate = total > 0 ? (presentCount / total) * 100.0 : 0.0;

      priorities.add(
        DigitizationPriority(
          instrumentOrVoice: partName,
          missingCount: missingCount,
          presentCount: presentCount,
          totalEligibleSongs: total,
          completionRate: rate,
          songsMissing: missingReports.map((r) => r.song).toList(),
        ),
      );
    });

    priorities.sort((a, b) {
      final cmp = b.missingCount.compareTo(a.missingCount);
      if (cmp != 0) return cmp;
      return a.completionRate.compareTo(b.completionRate);
    });

    return priorities.take(maxResults).toList();
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
        priorities: [],
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
    final priorities = calculatePriorities(reports);

    return DigitizationSummary(
      totalSongs: reports.length,
      completeSongs: completeCount,
      incompleteSongs: incompleteCount,
      totalMissingParts: missingTotal,
      overallPercentage: overallPct,
      missingByInstrument: sortedMissingMap,
      priorities: priorities,
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
    final summary = calculateSummary(reports);

    buffer.writeln('📋 *Notencloud - Fehlende Noten zum Digitalisieren*');
    buffer.writeln('Stand: $dateStr • Gesamt-Digitalisierung: ${summary.overallPercentage.round()}%');
    buffer.writeln('${filtered.length} unvollständige Stücke\n');

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
    final summary = calculateSummary(reports);
    page.graphics.drawString(
      '$orchestraName • Stand: $dateStr • Gesamt-Score: ${summary.overallPercentage.round()}% • ${filtered.length} unvollständige Stücke',
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
