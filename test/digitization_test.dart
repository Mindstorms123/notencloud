import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notencloud/models/song.dart';
import 'package:notencloud/services/digitization_service.dart';
import 'package:notencloud/services/storage_service.dart';
import 'package:notencloud/services/voice_matcher.dart';
import 'package:notencloud/ui/screens/digitization_audit_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Song createSampleSong({
    required String title,
    required String category,
    required List<String> fileNames,
  }) {
    final songId = title.replaceAll(' ', '_');
    final parts = fileNames.map((name) {
      return VoiceMatcher.parsePartFileName(name, songId, '/local/$songId/$name');
    }).toList();

    return Song(
      id: songId,
      title: title,
      category: category,
      folderName: title,
      remoteFolderPath: '/Noten/$category/$title',
      parts: parts,
    );
  }

  group('DigitizationService Analysis', () {
    test('detects internal register gaps in an instrument section', () {
      final song = createSampleSong(
        title: 'Polka No 1',
        category: 'Polka',
        fileNames: [
          'Trompete 1 in Bb.pdf',
          'Trompete 3 in Bb.pdf', // Trompete 2 is missing!
          'Flöte 1 in C.pdf',
          'Flöte 2 in C.pdf',
        ],
      );

      final reportLuecken = DigitizationService.analyzeSong(song, mode: AuditMode.registerLuecken);
      expect(reportLuecken.missingParts, contains('Trompete 2'));
      expect(reportLuecken.missingParts, isNot(contains('Flöte 1')));
      expect(reportLuecken.missingParts, isNot(contains('Flöte 2')));
      expect(reportLuecken.isComplete, false);
    });

    test('combined voice (e.g. 1-2) satisfies both voice 1 and 2', () {
      final song = createSampleSong(
        title: 'Walzer No 2',
        category: 'Walzer',
        fileNames: [
          'Waldhorn 1-2 in F.pdf', // Combined Horn 1 and 2
        ],
      );

      final reportLuecken = DigitizationService.analyzeSong(song, mode: AuditMode.registerLuecken);
      expect(reportLuecken.missingParts, isNot(contains('Waldhorn 1')));
      expect(reportLuecken.missingParts, isNot(contains('Waldhorn 2')));
    });

    test('checks standard core blasorchester requirements', () {
      final incompleteSong = createSampleSong(
        title: 'Marsch 1',
        category: 'Marsch',
        fileNames: [
          'Trompete 1 in Bb.pdf',
        ],
      );

      final report = DigitizationService.analyzeSong(incompleteSong, mode: AuditMode.standardBesetzung);
      expect(report.isComplete, false);
      expect(report.missingParts, contains('Trompete 2 (Bb)'));
      expect(report.missingParts, contains('Flöte 1 (C)'));
      expect(report.missingParts, contains('Partitur'));
      expect(report.completionPercentage, lessThan(100.0));
    });

    test('ignores documents and setlists as already complete', () {
      final docSong = Song(
        id: 'doc_1',
        title: 'Ablaufplan 2026',
        category: 'Listen und Co',
        folderName: 'Ablaufplan 2026',
        remoteFolderPath: '/Noten/Listen und Co/Ablaufplan 2026',
        parts: [
          VoiceMatcher.parsePartFileName('Ablaufplan.pdf', 'doc_1', '/local/Ablaufplan.pdf'),
        ],
      );

      final report = DigitizationService.analyzeSong(docSong);
      expect(report.isComplete, true);
      expect(report.missingParts, isEmpty);
      expect(report.completionPercentage, 100.0);
    });
  });

  group('DigitizationService Summary and Text Sharing', () {
    test('calculateSummary accurately aggregates reports', () {
      final song1 = createSampleSong(
        title: 'Song 1',
        category: 'Marsch',
        fileNames: ['Trompete 1 in Bb.pdf', 'Trompete 2 in Bb.pdf'],
      );
      final song2 = createSampleSong(
        title: 'Song 2',
        category: 'Polka',
        fileNames: ['Trompete 1 in Bb.pdf', 'Trompete 3 in Bb.pdf'],
      );

      final reports = DigitizationService.analyzeAllSongs([song1, song2], mode: AuditMode.registerLuecken);
      final summary = DigitizationService.calculateSummary(reports);

      expect(summary.totalSongs, 2);
      expect(summary.incompleteSongs, 1);
      expect(summary.completeSongs, 1);
      expect(summary.totalMissingParts, 1);
      expect(summary.missingByInstrument['Trompete 2'], 1);
    });

    test('generateShareText formats text with stats and missing items', () {
      final song = createSampleSong(
        title: 'Alte Kameraden',
        category: 'Marsch',
        fileNames: ['Trompete 1 in Bb.pdf', 'Trompete 3 in Bb.pdf'],
      );

      final reports = DigitizationService.analyzeAllSongs([song], mode: AuditMode.registerLuecken);
      final text = DigitizationService.generateShareText(reports);

      expect(text, contains('Fehlende Noten zum Digitalisieren'));
      expect(text, contains('Alte Kameraden'));
      expect(text, contains('Trompete 2'));
    });
  });

  group('DigitizationAuditScreen Widget Tests', () {
    late StorageService storageService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      storageService = StorageService(prefs);
    });

    testWidgets('renders audit screen with stats, search, and list', (tester) async {
      final song = createSampleSong(
        title: 'Böhmischer Traum',
        category: 'Polka',
        fileNames: [
          'Trompete 1 in Bb.pdf',
          'Trompete 3 in Bb.pdf',
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: DigitizationAuditScreen(
            allSongs: [song],
            storageService: storageService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check title & stats bar
      expect(find.text('Digitalisierungs-Check'), findsOneWidget);
      expect(find.text('Stücke'), findsOneWidget);
      expect(find.text('Vollständig'), findsOneWidget);
      expect(find.text('Unvollständig'), findsOneWidget);

      // Check song title present in the list
      expect(find.text('Böhmischer Traum'), findsOneWidget);

      // Tap on the song to open details bottom sheet
      await tester.tap(find.text('Böhmischer Traum'));
      await tester.pumpAndSettle();

      // Check modal content (FEHLENDE STIMMEN is at the top of the modal)
      expect(find.textContaining('FEHLENDE STIMMEN'), findsOneWidget);
      expect(find.text('Noch einscannen'), findsWidgets);
    });
  });
}
