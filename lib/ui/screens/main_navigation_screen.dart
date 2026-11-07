import 'package:flutter/material.dart';
import '../../models/musician_profile.dart';
import '../../models/nextcloud_account.dart';
import '../../services/annotation_service.dart';
import '../../services/nextcloud_service.dart';
import '../../services/storage_service.dart';
import 'repertoire_screen.dart';
import 'setlists_screen.dart';
import 'settings_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  final StorageService storageService;

  const MainNavigationScreen({
    super.key,
    required this.storageService,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  late MusicianProfile _profile;
  late NextcloudAccount _account;
  late AnnotationService _annotationService;
  NextcloudService? _nextcloudService;

  @override
  void initState() {
    super.initState();
    _profile = widget.storageService.getProfile();
    _account = widget.storageService.getAccount();
    _annotationService = AnnotationService(widget.storageService);
    if (_account.isConfigured) {
      _nextcloudService = NextcloudService(_account);
    }
  }

  void _onProfileUpdated(MusicianProfile newProfile) {
    setState(() {
      _profile = newProfile;
    });
  }

  void _onAccountUpdated(NextcloudAccount newAccount) {
    setState(() {
      _account = newAccount;
      _nextcloudService = newAccount.isConfigured ? NextcloudService(newAccount) : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      RepertoireScreen(
        storageService: widget.storageService,
        annotationService: _annotationService,
        nextcloudService: _nextcloudService,
        profile: _profile,
      ),
      SetlistsScreen(
        storageService: widget.storageService,
        annotationService: _annotationService,
        nextcloudService: _nextcloudService,
        profile: _profile,
      ),
      SettingsScreen(
        storageService: widget.storageService,
        onProfileUpdated: _onProfileUpdated,
        onAccountUpdated: _onAccountUpdated,
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) {
          setState(() {
            _currentIndex = idx;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music),
            label: 'Noten',
          ),
          NavigationDestination(
            icon: Icon(Icons.format_list_bulleted_outlined),
            selectedIcon: Icon(Icons.format_list_bulleted),
            label: 'Setlisten',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Einstellungen',
          ),
        ],
      ),
    );
  }
}
