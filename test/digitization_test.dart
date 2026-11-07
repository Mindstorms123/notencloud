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

    test('considers Life on Mars Bb Trumpet Cornet I as covering Trompete 1', () {
      final song = createSampleSong(
        title: 'Life on Mars',
        category: 'Rock',
        fileNames: [
          'LIFE ON MARS - Bb Trumpet Cornet I.pdf',
        ],
      );

      final report = DigitizationService.analyzeSong(song, mode: AuditMode.standardBesetzung);
      // Trompete 1 (Bb) should NOT be missing because 'Bb Trumpet Cornet I' is present!
      expect(report.missingParts, isNot(contains('Trompete 1 (Bb)')));
      expect(report.presentParts, contains('Trompete 1 in Bb'));
    });

    test('smart mode does not demand Flügelhorn on modern Pop/Rock arrangements', () {
      final rockSong = createSampleSong(
        title: 'Life on Mars',
        category: 'Rock',
        fileNames: [
          'LIFE ON MARS - Bb Trumpet Cornet I.pdf',
          'LIFE ON MARS - Bb Trumpet 2.pdf',
        ],
      );

      final smartReport = DigitizationService.analyzeSong(rockSong, mode: AuditMode.smartBesetzung);
      // In smart mode, Flügelhorn should NOT be demanded for a Rock song without Flügelhorn parts!
      expect(smartReport.missingParts, isNot(contains('Flügelhorn 1 (Bb)')));
      expect(smartReport.missingParts, isNot(contains('Flügelhorn 2 (Bb)')));

      // But in strict classical standardBesetzung mode, it is still checked if user explicitly wants it
      final strictReport = DigitizationService.analyzeSong(rockSong, mode: AuditMode.standardBesetzung);
      expect(strictReport.missingParts, contains('Flügelhorn 1 (Bb)'));
    });

    test('manual ignore (Nicht im Original) removes missing part and increases completion', () {
      final song = createSampleSong(
        title: 'Polka No 1',
        category: 'Polka',
        fileNames: ['Trompete 1 in Bb.pdf', 'Trompete 3 in Bb.pdf'],
      );

      final reportBefore = DigitizationService.analyzeSong(song, mode: AuditMode.registerLuecken);
      expect(reportBefore.missingParts, contains('Trompete 2'));
      expect(reportBefore.isComplete, false);

      // Mark Trompete 2 as ignored (nicht im Original)
      final reportAfter = DigitizationService.analyzeSong(
        song,
        mode: AuditMode.registerLuecken,
        ignoredParts: ['Trompete 2'],
      );
      expect(reportAfter.missingParts, isNot(contains('Trompete 2')));
      expect(reportAfter.isComplete, true);
      expect(reportAfter.completionPercentage, 100.0);
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

    test('calculatePriorities correctly ranks voices by highest missing count and lowest rate', () {
      final song1 = createSampleSong(
        title: 'Song 1',
        category: 'Marsch',
        fileNames: ['Trompete 1 in Bb.pdf', 'Trompete 3 in Bb.pdf'], // Trompete 2 missing
      );
      final song2 = createSampleSong(
        title: 'Song 2',
        category: 'Marsch',
        fileNames: ['Trompete 1 in Bb.pdf', 'Trompete 3 in Bb.pdf', 'Posaune 1.pdf', 'Posaune 3.pdf'], // Trompete 2 & Posaune 2 missing
      );

      final reports = DigitizationService.analyzeAllSongs([song1, song2], mode: AuditMode.registerLuecken);
      final priorities = DigitizationService.calculatePriorities(reports);

      expect(priorities, isNotEmpty);
      // Trompete 2 is missing in both songs, so it should be rank #1!
      expect(priorities.first.instrumentOrVoice, 'Trompete 2');
      expect(priorities.first.missingCount, 2);
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
      expect(text, contains('Gesamt-Digitalisierung'));
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
      expect(find.text('Gesamt-Digitalisierungsscore'), findsOneWidget);
      expect(find.text('Smart-Besetzung (Auto)'), findsOneWidget);
      expect(find.text('Empfohlene nächste Digitalisierungs-Ziele'), findsOneWidget);
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

    testWidgets('prioritizes selected instrument missing parts to the very front', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() async => await tester.binding.setSurfaceSize(null));

      final song = createSampleSong(
        title: 'Medley 2026',
        category: 'Modern',
        fileNames: [
          'Altsaxophon 1.pdf',
          'Flöte 2.pdf', // Flöte 1 missing
          'Trompete 1 in Bb.pdf',
          'Trompete 3 in Bb.pdf', // Trompete 2 missing
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

      // Tap 'Alle Instrumente' dropdown to open choices
      await tester.tap(find.text('Alle Instrumente'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Trompete').last);
      await tester.pumpAndSettle();

      // Star icon should appear for prioritized instrument
      expect(find.byIcon(Icons.star_rounded), findsWidgets);
      expect(find.text('Fehlt: Trompete 2 (Bb)'), findsOneWidget);
    });
  });
}
