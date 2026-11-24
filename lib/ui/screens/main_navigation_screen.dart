import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/musician_profile.dart';
import '../../models/nextcloud_account.dart';
import '../../services/annotation_service.dart';
import '../../services/nextcloud_service.dart';
import '../../services/storage_service.dart';
import '../theme/app_theme.dart';
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

class _MainNavigationScreenState extends State<MainNavigationScreen> with WidgetsBindingObserver {
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
    // Notizen, die ohne Internet entstanden sind, nachreichen: beim Start, wenn
    // die App wieder nach vorne kommt, und solange sie offen ist jede Minute.
    WidgetsBinding.instance.addObserver(this);
    _pendingSyncTimer = Timer.periodic(const Duration(seconds: 60), (_) => _syncPendingNotes());
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPendingNotes());
  }

  Timer? _pendingSyncTimer;

  Future<void> _syncPendingNotes() async {
    final service = _nextcloudService;
    if (service == null || widget.storageService.getPendingAnnotationUploads().isEmpty) return;
    final uploaded = await _annotationService.syncPendingUploads(service);
    if (uploaded > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.emerald,
          content: Text(
            uploaded == 1
                ? 'Eine Notizseite wurde in die Nextcloud übertragen.'
                : '$uploaded Notizseiten wurden in die Nextcloud übertragen.',
          ),
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncPendingNotes();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pendingSyncTimer?.cancel();
    super.dispose();
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
        onProfileUpdated: _onProfileUpdated,
      ),
      SetlistsScreen(
        storageService: widget.storageService,
        annotationService: _annotationService,
        nextcloudService: _nextcloudService,
        profile: _profile,
      ),
      SettingsScreen(
        storageService: widget.storageService,
        profile: _profile,
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
