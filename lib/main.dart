import 'package:flutter/material.dart';
import 'services/storage_service.dart';
import 'ui/screens/main_navigation_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5), // Blue 600
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          brightness: Brightness.dark,
          surface: const Color(0xFF181818),
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor: Color(0xFF181818),
        ),
      ),
      home: MainNavigationScreen(storageService: storageService),
    );
  }
}
