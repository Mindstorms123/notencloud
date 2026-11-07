import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/storage_service.dart';
import 'ui/screens/main_navigation_screen.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
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

  const NotencloudApp({super.key, required this.storageService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notencloud',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark, // Default to sleek Stage Dark Mode
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: MainNavigationScreen(storageService: storageService),
    );
  }
}
