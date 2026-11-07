import 'package:flutter_test/flutter_test.dart';
import 'package:notencloud/main.dart';
import 'package:notencloud/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App smoke test and navigation tabs render', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final storageService = await StorageService.init();

    await tester.pumpWidget(NotencloudApp(storageService: storageService));
    await tester.pumpAndSettle();

    // Verify navigation tabs
    expect(find.text('Noten'), findsWidgets);
    expect(find.text('Setlisten'), findsOneWidget);
    expect(find.text('Einstellungen'), findsOneWidget);
  });
}
