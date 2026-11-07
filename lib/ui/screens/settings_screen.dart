import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/musician_profile.dart';
import '../../models/nextcloud_account.dart';
import '../../services/nextcloud_service.dart';
import '../../services/storage_service.dart';
import '../../services/voice_matcher.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  final StorageService storageService;
  final Function(MusicianProfile) onProfileUpdated;
  final Function(NextcloudAccount) onAccountUpdated;

  const SettingsScreen({
    super.key,
    required this.storageService,
    required this.onProfileUpdated,
    required this.onAccountUpdated,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late MusicianProfile _profile;
  late NextcloudAccount _account;

  final _serverUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _rootFolderController = TextEditingController();

  bool _isTestingConnection = false;
  String? _connectionTestResult;
  bool _isConnectionSuccess = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.storageService.getProfile();
    _account = widget.storageService.getAccount();

    _serverUrlController.text = _account.serverUrl;
    _usernameController.text = _account.username;
    _passwordController.text = _account.password;
    _rootFolderController.text = _account.rootFolder;
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _rootFolderController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    await widget.storageService.saveProfile(_profile);
    widget.onProfileUpdated(_profile);
  }

  Future<void> _saveAccount() async {
    final updated = _account.copyWith(
      serverUrl: _serverUrlController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text.trim(),
      rootFolder: _rootFolderController.text.trim(),
    );
    await widget.storageService.saveAccount(updated);
    _account = updated;
    widget.onAccountUpdated(updated);
  }

  Future<void> _testConnection() async {
    await _saveAccount();
    if (!_account.isConfigured) {
      setState(() {
        _connectionTestResult = 'Bitte Server-URL, Benutzername und Passwort ausfüllen.';
        _isConnectionSuccess = false;
      });
      return;
    }

    setState(() {
      _isTestingConnection = true;
      _connectionTestResult = null;
    });

    final service = NextcloudService(_account);
    final success = await service.testConnection();

    setState(() {
      _isTestingConnection = false;
      _isConnectionSuccess = success;
      _connectionTestResult = success
          ? 'Verbindung zu Nextcloud erfolgreich hergestellt!'
          : 'Verbindungsfehler: Bitte URL und Zugangsdaten prüfen.';
    });
  }

  Future<void> _startBrowserLoginFlow() async {
    final serverUrl = _serverUrlController.text.trim().isNotEmpty
        ? _serverUrlController.text.trim()
        : 'https://cloud.blasorchester-1862.de/';
    _serverUrlController.text = serverUrl;

    setState(() {
      _isTestingConnection = true;
      _connectionTestResult = 'Starte Nextcloud Browser-Login...';
    });

    final flow = await NextcloudService.initLoginFlow(serverUrl);
    if (flow == null) {
      setState(() {
        _isTestingConnection = false;
        _isConnectionSuccess = false;
        _connectionTestResult = 'Login-Flow konnte nicht initialisiert werden. Bitte Server-URL prüfen.';
      });
      return;
    }

    final loginUri = Uri.parse(flow.loginUrl);
    if (!await launchUrl(loginUri, mode: LaunchMode.externalApplication)) {
      setState(() {
        _isTestingConnection = false;
        _isConnectionSuccess = false;
        _connectionTestResult = 'Web-Browser konnte nicht automatisch geöffnet werden.';
      });
      return;
    }

    // Show waiting dialog while polling Nextcloud
    bool isCancelled = false;
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: AppTheme.darkCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.open_in_browser_rounded, color: AppTheme.primaryLight),
              SizedBox(width: 10),
              Text('Im Browser anmelden', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppTheme.primaryLight),
              SizedBox(height: 18),
              Text(
                'Dein Web-Browser wurde geöffnet.\n\nBitte melde dich wie gewohnt an und tippe auf "Zugriff gewähren".',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppTheme.darkTextSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                isCancelled = true;
                Navigator.pop(dialogCtx);
              },
              child: const Text('Abbrechen', style: TextStyle(color: AppTheme.darkTextMuted)),
            ),
          ],
        ),
      );
    }

    // Poll Nextcloud every 1.5 seconds for up to 2.5 minutes
    final startTime = DateTime.now();
    while (!isCancelled && DateTime.now().difference(startTime).inSeconds < 150) {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (isCancelled || !mounted) break;

      final creds = await NextcloudService.pollLoginFlow(flow.pollEndpoint, flow.pollToken);
      if (creds != null) {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context); // Close waiting dialog
        }
        setState(() {
          _usernameController.text = creds.loginName;
          _passwordController.text = creds.appPassword;
          if (_rootFolderController.text.trim().isEmpty) {
            _rootFolderController.text = '/Noten';
          }
        });
        await _saveAccount();
        await _testConnection();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.emerald,
              content: Text('Erfolgreich als "${creds.loginName}" verbunden!'),
            ),
          );
        }
        return;
      }
    }

    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
    setState(() {
      _isTestingConnection = false;
      _isConnectionSuccess = false;
      _connectionTestResult = isCancelled
          ? 'Anmeldung abgebrochen.'
          : 'Zeitfenster für Bestätigung im Browser abgelaufen.';
    });
  }

  void _shareConnectionInfo() {
    final server = _serverUrlController.text.trim().isNotEmpty
        ? _serverUrlController.text.trim()
        : 'https://cloud.blasorchester-1862.de/';
    final folder = _rootFolderController.text.trim().isNotEmpty
        ? _rootFolderController.text.trim()
        : '/Noten';

    final text = '🎵 Blasorchester Notencloud Einrichtung:\n\n'
        '1. Notencloud-App installieren\n'
        '2. In den Einstellungen auf "Im Browser anmelden" tippen\n'
        '3. Server-URL: $server\n'
        '4. Notenordner: $folder\n'
        '5. Auf "Zugriff gewähren" tippen – fertig!';

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AppTheme.emerald,
        content: Text('Einrichtungs-Info kopiert! Kann per WhatsApp / Signal geteilt werden.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showGuidelineDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.lightbulb_rounded, color: AppTheme.amber),
            SizedBox(width: 10),
            Text('Noten-Ordner Guideline', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Damit die App deine Stimme automatisch findet, empfehlen wir folgende Struktur auf der Nextcloud:',
                style: TextStyle(fontSize: 13, color: AppTheme.darkTextSecondary),
              ),
              SizedBox(height: 14),
              Text(
                '1. Kategorie- und Lieder-Ordner:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              SizedBox(height: 6),
              Text(
                'Nextcloud/Noten/\n'
                '├── 01_Aktuelle Noten/\n'
                '│   └── Under Pressure/\n'
                '│       ├── Partitur.pdf\n'
                '│       ├── Trumpet/ (Stimmordner)\n'
                '│       │   ├── 1. Trumpet.pdf\n'
                '│       │   └── 2. Trumpet.pdf\n'
                '│       └── Trombone/ ...\n'
                '└── 02_Ältere Noten/...',
                style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppTheme.primaryLight),
              ),
              SizedBox(height: 14),
              Text(
                '2. Benennung der Stimmen:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              SizedBox(height: 6),
              Text(
                '• Trompete_1_Bb.pdf\n'
                '• 1. Trumpet.pdf (im Ordner Trumpet)\n'
                '• Klarinette_2_Bb.pdf\n'
                '• Altsaxophon_1_Eb.pdf\n'
                '• Posaune_1_C.pdf\n'
                '• Horn_1-2_in_F.pdf (Kombistimme)',
                style: TextStyle(fontSize: 12, color: AppTheme.darkTextSecondary),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Verstanden'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cachedSongs = widget.storageService.getCachedSongs();
    final dynamicInstruments = VoiceMatcher.getAvailableInstruments(cachedSongs);
    final instrumentsList = [
      ...dynamicInstruments,
      if (!dynamicInstruments.contains(_profile.instrument)) _profile.instrument,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B5CF6), AppTheme.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.tune_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Profil & Einstellungen',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: 'Noten-Guideline ansehen',
            onPressed: _showGuidelineDialog,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Section 1: Musician Profile
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.emerald.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.person_rounded, color: AppTheme.emerald, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Dein Musiker-Profil',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          dynamicInstruments.isNotEmpty
                              ? '${dynamicInstruments.length} Register aus Cloud erkannt'
                              : 'Automatische Stimmen-Zuweisung',
                          style: const TextStyle(fontSize: 12, color: AppTheme.darkTextMuted),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Dynamic Instrument selector
                DropdownButtonFormField<String>(
                  value: instrumentsList.contains(_profile.instrument)
                      ? _profile.instrument
                      : instrumentsList.firstOrNull ?? 'Trompete',
                  decoration: InputDecoration(
                    labelText: 'Instrument (${instrumentsList.length} in Cloud)',
                    prefixIcon: const Icon(Icons.music_note_rounded),
                  ),
                  items: instrumentsList.map((inst) {
                    return DropdownMenuItem(value: inst, child: Text(inst));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _profile = _profile.copyWith(instrument: val);
                      });
                      _saveProfile();
                    }
                  },
                ),
                const SizedBox(height: 14),

                Row(
                  children: [
                    // Voice number
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: _profile.voiceNumber,
                        decoration: const InputDecoration(
                          labelText: 'Stimme',
                        ),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Keine / Alle')),
                          DropdownMenuItem(value: 1, child: Text('1. Stimme')),
                          DropdownMenuItem(value: 2, child: Text('2. Stimme')),
                          DropdownMenuItem(value: 3, child: Text('3. Stimme')),
                          DropdownMenuItem(value: 4, child: Text('4. Stimme')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _profile = _profile.copyWith(voiceNumber: val);
                            });
                            _saveProfile();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Key / Transposition
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: MusicianProfile.standardKeys.contains(_profile.keyOrClef)
                            ? _profile.keyOrClef
                            : 'Bb',
                        decoration: const InputDecoration(
                          labelText: 'Stimmung',
                        ),
                        items: MusicianProfile.standardKeys.map((k) {
                          return DropdownMenuItem(value: k, child: Text(k));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _profile = _profile.copyWith(keyOrClef: val);
                            });
                            _saveProfile();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Section 2: Nextcloud Account
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.cloud_rounded, color: AppTheme.primaryLight, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Nextcloud-Verbindung',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Synchronisation & Setlisten',
                          style: TextStyle(fontSize: 12, color: AppTheme.darkTextMuted),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // 1-Click Browser Login Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primary.withValues(alpha: 0.2),
                        AppTheme.primaryLight.withValues(alpha: 0.08),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded, color: AppTheme.primaryLight, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Ein-Klick Nextcloud Browser-Login',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppTheme.primaryLight,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Öffnet deinen Browser für die Anmeldung. Einfach auf "Zugriff gewähren" tippen – kein Passwort-Abtippen nötig!',
                        style: TextStyle(fontSize: 12, color: AppTheme.darkTextSecondary),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 11),
                              ),
                              onPressed: _isTestingConnection ? null : _startBrowserLoginFlow,
                              icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                              label: const Text('Im Browser anmelden', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            style: IconButton.styleFrom(
                              backgroundColor: AppTheme.darkSurface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(color: AppTheme.darkBorder),
                              ),
                            ),
                            icon: const Icon(Icons.share_rounded, size: 18, color: AppTheme.primaryLight),
                            tooltip: 'Einrichtung für Kollegen teilen',
                            onPressed: _shareConnectionInfo,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const Row(
                  children: [
                    Expanded(child: Divider(color: AppTheme.darkBorder)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text('oder manuell eingeben', style: TextStyle(fontSize: 11, color: AppTheme.darkTextMuted)),
                    ),
                    Expanded(child: Divider(color: AppTheme.darkBorder)),
                  ],
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _serverUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Server-URL',
                    hintText: 'https://cloud.mein-orchester.de',
                    prefixIcon: Icon(Icons.link_rounded),
                  ),
                  onChanged: (_) => _saveAccount(),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Benutzername / E-Mail',
                    prefixIcon: Icon(Icons.account_circle_rounded),
                  ),
                  onChanged: (_) => _saveAccount(),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Passwort / App-Token',
                    prefixIcon: Icon(Icons.lock_rounded),
                  ),
                  onChanged: (_) => _saveAccount(),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _rootFolderController,
                  decoration: const InputDecoration(
                    labelText: 'Notenordner',
                    hintText: '/Noten',
                    prefixIcon: Icon(Icons.folder_rounded),
                  ),
                  onChanged: (_) => _saveAccount(),
                ),
                const SizedBox(height: 16),

                if (_connectionTestResult != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: _isConnectionSuccess
                          ? AppTheme.emerald.withValues(alpha: 0.12)
                          : AppTheme.rose.withValues(alpha: 0.12),
                      border: Border.all(
                        color: _isConnectionSuccess
                            ? AppTheme.emerald.withValues(alpha: 0.3)
                            : AppTheme.rose.withValues(alpha: 0.3),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isConnectionSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
                          color: _isConnectionSuccess ? AppTheme.emerald : AppTheme.rose,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _connectionTestResult!,
                            style: TextStyle(
                              color: _isConnectionSuccess ? AppTheme.emerald : AppTheme.rose,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _isTestingConnection ? null : _testConnection,
                  icon: _isTestingConnection
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.wifi_tethering_rounded),
                  label: const Text('Verbindung testen & speichern', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Guideline Info Card
          Material(
            color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _showGuidelineDialog,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.amber.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.lightbulb_rounded, color: AppTheme.amber, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Noten-Ordner Guideline', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Text('Empfohlene Benennung für Lieder & Stimmen', style: TextStyle(fontSize: 12, color: AppTheme.darkTextMuted)),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, size: 14, color: isDark ? AppTheme.darkTextMuted : Colors.grey.shade400),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
