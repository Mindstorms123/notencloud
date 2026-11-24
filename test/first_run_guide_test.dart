import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notencloud/models/song.dart';
import 'package:notencloud/services/storage_service.dart';
import 'package:notencloud/ui/widgets/first_run_guide.dart';
import 'package:shared_preferences/shared_preferences.dart';

Song _song(String id, String category, String partName, String instrument) => Song(
      id: id,
      title: id,
      folderName: id,
      remoteFolderPath: '/Noten/$id',
      category: category,
      parts: [
        PartFile(
          id: '${id}_p',
          songId: id,
          fileName: partName,
          remotePath: '/Noten/$id/$partName',
          detectedInstrument: instrument,
          detectedVoice: 1,
        ),
      ],
    );

void main() {
  Future<StorageService> open(
    WidgetTester tester,
    Map<String, Object> prefs, {
    LibraryLoader? loadLibrary,
  }) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(prefs);
    final storage = StorageService(await SharedPreferences.getInstance());
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => FirstRunGuide.showIfNeeded(context, storage, loadLibrary: loadLibrary),
          child: const Text('start'),
        ),
      ),
    ));
    await tester.tap(find.text('start'));
    await tester.pump();
    return storage;
  }

  testWidgets('guides through library, instrument, start folder and tips', (tester) async {
    final gate = Completer<void>();
    final storage = await open(
      tester,
      {},
      loadLibrary: (onProgress) async {
        onProgress(1, 2);
        await gate.future;
        return [
          _song('Marsch', 'Aktuelle Noten', 'Tuba 1.pdf', 'Tuba'),
          _song('Polka', 'Ältere Noten', 'Flöte 1.pdf', 'Flöte'),
        ];
      },
    );

    // Schritt 1: Archiv wird geladen
    await tester.pump();
    expect(find.text('Schritt 1 von 4'), findsOneWidget);
    expect(find.text('1 von 2 Stücken gelesen'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();

    // Schritt 2: Instrumente stammen aus dem geladenen Archiv
    expect(find.text('Schritt 2 von 4'), findsOneWidget);
    expect(storage.getCachedSongs().length, 2);
    await tester.tap(find.text('Trompete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tuba').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    expect(storage.getProfile().instrument, 'Tuba');

    // Schritt 3: Startordner
    expect(find.text('Schritt 3 von 4'), findsOneWidget);
    await tester.tap(find.text('Ältere Noten'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    expect(storage.getDefaultCategory(), 'Ältere Noten');
    expect(storage.getLastActiveCategory(), 'Ältere Noten');

    // Schritt 4: Hinweise, dann schließen
    expect(find.text('Schritt 4 von 4'), findsOneWidget);
    expect(find.textContaining('Du spielst Tuba'), findsOneWidget);
    await tester.tap(find.text('Loslegen'));
    await tester.pumpAndSettle();
    expect(find.text('Schritt 4 von 4'), findsNothing);
  });

  testWidgets('continues without library when loading fails', (tester) async {
    final storage = await open(tester, {}, loadLibrary: (_) async => throw Exception('kein Netz'));
    await tester.pumpAndSettle();
    expect(find.textContaining('konnte nicht geladen werden'), findsOneWidget);
    expect(find.textContaining('kein Netz'), findsOneWidget);

    await tester.tap(find.text('Ohne Archiv weiter'));
    await tester.pumpAndSettle();
    expect(find.text('Schritt 2 von 4'), findsOneWidget);
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    // Ohne Ordner entfällt Schritt 3.
    expect(find.text('Schritt 4 von 4'), findsOneWidget);
    expect(storage.hasSavedProfile(), isTrue);
  });

  testWidgets('does not appear once a profile is saved', (tester) async {
    await open(tester, {
      'musician_profile':
          '{"instrument":"Tuba","voiceNumber":1,"keyOrClef":"","customVoiceName":"","percussionInstrument":""}',
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Schritt'), findsNothing);
  });
}
