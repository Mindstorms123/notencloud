import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/storage_service.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/main_navigation_screen.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Override Flutter's default red ErrorWidget with a clean, dark stage error fallback
  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint('Flutter ErrorWidget caught UI exception: ${details.exceptionAsString()}');
    return Material(
      color: AppTheme.darkBg,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppTheme.primaryLight),
            SizedBox(height: 16),
            Text(
              'Lade Noten...',
              style: TextStyle(color: AppTheme.darkTextSecondary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  };
  
  // Initialize German locale data for DateFormat
  await initializeDateFormatting('de_DE', null);

  // Set transparent status bar with light icons for dark stage theme
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  final storageService = await StorageService.init();
  runApp(NotencloudApp(storageService: storageService));
}

class NotencloudApp extends StatelessWidget {
  final StorageService storageService;
  final bool? isConfiguredOverride;

  const NotencloudApp({
    super.key,
    required this.storageService,
    this.isConfiguredOverride,
  });

  @override
  Widget build(BuildContext context) {
    final isConfigured = isConfiguredOverride ?? storageService.getAccount().isConfigured;

    return MaterialApp(
      title: 'Notencloud',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark, // Default to sleek Stage Dark Mode
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: isConfigured
          ? MainNavigationScreen(storageService: storageService)
          : LoginScreen(storageService: storageService),
    );
  }
}
