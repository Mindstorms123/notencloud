import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:notencloud/main.dart';
import 'package:notencloud/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('de_DE', null);
  });
  testWidgets('App renders LoginScreen on first start when not configured', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final storageService = await StorageService.init();

    await tester.pumpWidget(NotencloudApp(storageService: storageService));
    await tester.pumpAndSettle();

    // Verify LoginScreen is shown
    expect(find.text('Notencloud'), findsOneWidget);
    expect(find.text('Im Browser anmelden'), findsOneWidget);
    expect(find.text('Manuelle Anmeldung (Passwort / Token)'), findsOneWidget);
  });

  testWidgets('App smoke test and navigation tabs render when configured', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'nextcloud_account': '{"serverUrl":"https://cloud.blasorchester-1862.de","username":"test","password":"secret","rootFolder":"/Noten","isValidated":true}',
    });
    final storageService = await StorageService.init();

    await tester.pumpWidget(NotencloudApp(
      storageService: storageService,
      isConfiguredOverride: true,
    ));
    await tester.pumpAndSettle();

    // Verify navigation tabs
    expect(find.text('Noten'), findsWidgets);
    expect(find.text('Setlisten'), findsOneWidget);
    expect(find.text('Einstellungen'), findsOneWidget);
  });

  testWidgets('Repertoire voice filter updates immediately when voice is changed in settings', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'nextcloud_account': '{"serverUrl":"https://cloud.blasorchester-1862.de","username":"test","password":"secret","rootFolder":"/Noten","isValidated":true}',
      'musician_profile': '{"instrument":"Trompete","voiceNumber":1,"keyOrClef":"Bb"}',
      'cached_songs_index': '[{"id":"song1","title":"Marsch der Trompeten","composer":"","category":"Aktuelle Noten","folderName":"Marsch der Trompeten","parts":[{"id":"p1","fileName":"Trompete_1_Bb.pdf","detectedInstrument":"Trompete","detectedVoice":1,"detectedKey":"Bb","isCombinedVoice":false,"remotePath":"/p1"},{"id":"p2","fileName":"Percussion.pdf","detectedInstrument":"Percussion","detectedVoice":1,"detectedKey":"","isCombinedVoice":false,"remotePath":"/p2"}]}]',
    });
    final storageService = await StorageService.init();

    await tester.pumpWidget(NotencloudApp(
      storageService: storageService,
      isConfiguredOverride: true,
    ));
    await tester.pumpAndSettle();

    // Verify initial filter pill shows Trompete 1 (Bb)
    expect(find.text('Trompete 1 (Bb)'), findsOneWidget);

    // Switch to Settings tab
    await tester.tap(find.text('Einstellungen'));
    await tester.pumpAndSettle();

    // Find and tap the Instrument Dropdown
    final instDropdown = find.text('Trompete');
    expect(instDropdown, findsOneWidget);
    await tester.tap(instDropdown);
    await tester.pumpAndSettle();

    // Select Percussion from the dropdown list
    final percOption = find.text('Percussion').last;
    await tester.tap(percOption);
    await tester.pumpAndSettle();

    // Switch back to Noten tab
    await tester.tap(find.text('Noten').first);
    await tester.pumpAndSettle();

    // The filter pill must now immediately reflect Percussion 1!
    expect(find.text('Percussion 1'), findsOneWidget);
    expect(find.text('Trompete 1 (Bb)'), findsNothing);

    // Verify Percussion quick-selector chips are visible
    expect(find.text('Pauken'), findsOneWidget);
    expect(find.text('Schlagzeug'), findsOneWidget);
    expect(find.text('Mallets'), findsOneWidget);

    // Tap the Pauken quick-selector chip directly on the Repertoire screen
    await tester.tap(find.text('Pauken'));
    await tester.pumpAndSettle();

    // The filter pill must immediately reflect the quick selection
    expect(find.text('Percussion (Pauken) 1'), findsOneWidget);
  });

  testWidgets('SetlistDetailScreen has Bearbeiten toggle and Gmail-style Zurückholen undo', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'nextcloud_account': '{"serverUrl":"https://cloud.blasorchester-1862.de","username":"test","password":"secret","rootFolder":"/Noten","isValidated":true}',
      'musician_profile': '{"instrument":"Trompete","voiceNumber":1,"keyOrClef":"Bb"}',
      'local_setlists': '[{"id":"sl1","title":"Konzert 2027","date":"2027-04-10T20:00:00.000","updatedAt":"2027-04-10T20:00:00.000","items":[{"id":"i1","songId":"s1","songTitle":"Don\'t Stop Believin\'","songFolderName":"Dont Stop Believin","order":1,"notes":"","isIntermission":false},{"id":"i2","songId":"s2","songTitle":"Music","songFolderName":"Music","order":2,"notes":"","isIntermission":false}]}]',
      'cached_songs_index': '[]',
    });
    final storageService = await StorageService.init();

    await tester.pumpWidget(NotencloudApp(
      storageService: storageService,
      isConfiguredOverride: true,
    ));
    await tester.pumpAndSettle();

    // Switch to Setlisten tab
    await tester.tap(find.text('Setlisten'));
    await tester.pumpAndSettle();

    // Verify Setlist is displayed
    expect(find.text('Konzert 2027'), findsOneWidget);

    // Open the setlist
    await tester.tap(find.text('Konzert 2027'));
    await tester.pumpAndSettle();

    // Verify pieces are visible
    expect(find.text("Don't Stop Believin'"), findsOneWidget);
    expect(find.text('Music'), findsOneWidget);

    // Bearbeiten button is present in AppBar
    final editButton = find.text('Bearbeiten');
    expect(editButton, findsOneWidget);

    // Enter edit mode
    await tester.tap(editButton);
    await tester.pumpAndSettle();

    // Verify edit mode banner & Fertig button
    expect(find.text('Fertig'), findsWidgets);
    expect(find.textContaining('Bearbeitungsmodus aktiv'), findsOneWidget);

    // Find the red minus remove button and delete the first song
    final removeButtons = find.byIcon(Icons.remove_circle_rounded);
    expect(removeButtons, findsNWidgets(2));
    await tester.tap(removeButtons.first);
    await tester.pumpAndSettle();

    // Don't Stop Believin' is removed from the list
    expect(find.text("Don't Stop Believin'"), findsNothing);
    expect(find.text('Music'), findsOneWidget);

    // SnackBar popup with ZURÜCKHOLEN is visible
    expect(find.textContaining('entfernt'), findsOneWidget);
    final undoButton = find.text('ZURÜCKHOLEN');
    expect(undoButton, findsOneWidget);

    // Tap ZURÜCKHOLEN
    await tester.tap(undoButton);
    await tester.pumpAndSettle();

    // Song is restored!
    expect(find.text("Don't Stop Believin'"), findsOneWidget);
  });
}
