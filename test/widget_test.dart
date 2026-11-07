import 'package:flutter_test/flutter_test.dart';
import 'package:notencloud/main.dart';
import 'package:notencloud/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
}
