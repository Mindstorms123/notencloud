import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notencloud/services/storage_service.dart';
import 'package:notencloud/ui/widgets/profile_setup_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<StorageService> pumpWithButton(WidgetTester tester, Map<String, Object> prefsValues) async {
    SharedPreferences.setMockInitialValues(prefsValues);
    final storage = StorageService(await SharedPreferences.getInstance());
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => ProfileSetupDialog.showIfNeeded(context, storage),
          child: const Text('start'),
        ),
      ),
    ));
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    return storage;
  }

  testWidgets('asks for instrument and voice on first login and saves the choice', (tester) async {
    final storage = await pumpWithButton(tester, {});
    expect(storage.hasSavedProfile(), isFalse);
    expect(find.text('Was spielst du?'), findsOneWidget);
    expect(find.text('Instrument'), findsOneWidget);
    expect(find.text('Stimme'), findsOneWidget);

    await tester.tap(find.text('Trompete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flügelhorn').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Speichern und loslegen'));
    await tester.pumpAndSettle();

    expect(find.text('Was spielst du?'), findsNothing);
    expect(storage.hasSavedProfile(), isTrue);
    expect(storage.getProfile().instrument, 'Flügelhorn');
  });

  testWidgets('does not ask again once a profile is saved', (tester) async {
    await pumpWithButton(tester, {
      'musician_profile': '{"instrument":"Tuba","voiceNumber":1,"keyOrClef":"","customVoiceName":"","percussionInstrument":""}',
    });
    expect(find.text('Was spielst du?'), findsNothing);
  });
}
