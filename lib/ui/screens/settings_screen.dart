import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/musician_profile.dart';
import '../../models/nextcloud_account.dart';
import '../../services/nextcloud_service.dart';
import '../../services/storage_service.dart';
import '../../services/update_service.dart';
import '../../services/voice_matcher.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  final StorageService storageService;
  final MusicianProfile profile;
  final Function(MusicianProfile) onProfileUpdated;
  final Function(NextcloudAccount) onAccountUpdated;

  const SettingsScreen({
    super.key,
    required this.storageService,
    required this.profile,
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
  late String _defaultCategory;

  bool _isCheckingUpdate = false;
  bool _isDownloadingUpdate = false;
  double _downloadProgress = 0.0;
  AppUpdateInfo? _updateInfo;
  String? _updateError;
  String _installedVersion = '1.0.0';

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _account = widget.storageService.getAccount();
    _defaultCategory = widget.storageService.getDefaultCategory();

    _serverUrlController.text = _account.serverUrl;
    _usernameController.text = _account.username;
    _passwordController.text = _account.password;
    _rootFolderController.text = _account.rootFolder;

    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() {
          _installedVersion = info.version;
        });
      }
    }).catchError((_) {});
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.profile != oldWidget.profile) {
      setState(() {
        _profile = widget.profile;
      });
    }
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

    if (success) {
      unawaited(service.ensureSetlistFolderExists());
    }

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

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Nextcloud trennen?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'Möchtest du das aktuelle Nextcloud-Konto abmelden? Bereits heruntergeladene Noten bleiben auf dem Gerät erhalten.',
          style: TextStyle(color: AppTheme.darkTextSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen', style: TextStyle(color: AppTheme.darkTextMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.rose,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Abmelden'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      const emptyAccount = NextcloudAccount(serverUrl: '', username: '', password: '');
      await widget.storageService.saveAccount(emptyAccount);
      setState(() {
        _account = emptyAccount;
        _usernameController.clear();
        _passwordController.clear();
        _connectionTestResult = null;
      });
      widget.onAccountUpdated(emptyAccount);
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => LoginScreen(storageService: widget.storageService)),
          (route) => false,
        );
      }
    }
  }

  void _shareConnectionInfo() {
    final server = _serverUrlController.text.trim().isNotEmpty
        ? _serverUrlController.text.trim()
        : 'https://cloud.blasorchester-1862.de/';
    final folder = _rootFolderController.text.trim().isNotEmpty
        ? _rootFolderController.text.trim()
        : '/Noten';

    final setupLink = 'notencloud://setup?server=${Uri.encodeQueryComponent(server)}&folder=${Uri.encodeQueryComponent(folder)}';

    final text = '🎵 Blasorchester Notencloud Einrichtung:\n\n'
        'Tippe auf den Einrichtungs-Link, um Notencloud automatisch mit unserem Archiv zu verbinden:\n'
        '$setupLink\n\n'
        '(Alternativ: Server: $server | Notenordner: $folder)\n\n'
        'Anschließend in der App einfach auf "Im Browser anmelden" tippen – fertig!';

    Clipboard.setData(ClipboardData(text: setupLink));
    SharePlus.instance.share(ShareParams(text: text, subject: 'Notencloud Einrichtung'));
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

  Future<void> _checkForUpdate() async {
    setState(() {
      _isCheckingUpdate = true;
      _updateError = null;
    });

    try {
      final info = await UpdateService().checkForUpdate();
      if (mounted) {
        setState(() {
          _isCheckingUpdate = false;
          _updateInfo = info;
        });
        if (!info.hasUpdate) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.emerald,
              content: Text('Notencloud ist mit Version v$_installedVersion auf dem neuesten Stand!'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingUpdate = false;
          _updateError = 'Update-Prüfung fehlgeschlagen: $e';
        });
      }
    }
  }

  Future<void> _downloadAndInstall(String apkUrl) async {
    setState(() {
      _isDownloadingUpdate = true;
      _downloadProgress = 0.0;
    });

    try {
      final result = await UpdateService().downloadAndInstallApk(
        apkUrl,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _downloadProgress = p;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isDownloadingUpdate = false;
        });
        if (result.type != ResultType.done) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.amber,
              content: Text('APK heruntergeladen (${result.message}). Bitte Installation bestätigen.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloadingUpdate = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.rose,
            content: Text('Fehler beim Herunterladen: $e'),
          ),
        );
      }
    }
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
    final cachedCats = cachedSongs.map((s) => s.category).where((c) => c.isNotEmpty).toSet().toList();
    cachedCats.sort();
    final categoriesList = [
      'Aktuelle Noten',
      ...cachedCats.where((c) => c != 'Aktuelle Noten'),
      'Alle',
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
                  key: ValueKey('inst_${_profile.instrument}'),
                  initialValue: instrumentsList.contains(_profile.instrument)
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
                      final def = MusicianProfile.getDefinition(val);
                      var newKey = _profile.keyOrClef;
                      if (def.validKeys.isEmpty) {
                        newKey = '';
                      } else if (!def.validKeys.any((k) => k.key == newKey)) {
                        newKey = def.defaultKey;
                      }

                      var newVoice = _profile.voiceNumber;
                      if (!def.validVoices.contains(newVoice)) {
                        newVoice = def.defaultVoice;
                      }

                      setState(() {
                        _profile = _profile.copyWith(
                          instrument: val,
                          keyOrClef: newKey,
                          voiceNumber: newVoice,
                        );
                      });
                      _saveProfile();
                    }
                  },
                ),
                const SizedBox(height: 14),

                Builder(
                  builder: (context) {
                    final validVoices = MusicianProfile.getValidVoices(_profile.instrument);
                    final effectiveVoice = validVoices.contains(_profile.voiceNumber)
                        ? _profile.voiceNumber
                        : validVoices.first;
                    final validKeys = MusicianProfile.getValidKeys(_profile.instrument);

                    return Row(
                      children: [
                        // Voice number
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            key: ValueKey('voice_${_profile.instrument}_$effectiveVoice'),
                            initialValue: effectiveVoice,
                            decoration: const InputDecoration(
                              labelText: 'Stimme',
                            ),
                            items: validVoices.map((v) {
                              return DropdownMenuItem(
                                value: v,
                                child: Text(v == 0 ? 'Keine / Alle' : '$v. Stimme'),
                              );
                            }).toList(),
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

                        // Key / Transposition (only shown if instrument has valid keys)
                        if (validKeys.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('key_${_profile.instrument}_${_profile.keyOrClef}'),
                              initialValue: validKeys.any((k) => k.key == _profile.keyOrClef)
                                  ? _profile.keyOrClef
                                  : validKeys.first.key,
                              decoration: const InputDecoration(
                                labelText: 'Stimmung',
                              ),
                              items: validKeys.map((k) {
                                return DropdownMenuItem(value: k.key, child: Text(k.label));
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
                      ],
                    );
                  },
                ),
                if (_profile.instrument == 'Percussion') ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    key: ValueKey('perc_sub_${_profile.percussionInstrument}'),
                    initialValue: _profile.percussionInstrument.isEmpty
                        ? 'Alle'
                        : (_profile.percussionInstrument == 'Percussion'
                            ? 'Schlagzeug'
                            : _profile.percussionInstrument),
                    decoration: const InputDecoration(
                      labelText: 'Schlagwerk-Instrument',
                      prefixIcon: Icon(Icons.album_rounded),
                      helperText: 'Standard-Instrument für Percussion (z.B. Schlagzeug, Pauken, Mallets)',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Alle', child: Text('Alle / Flexibel')),
                      DropdownMenuItem(value: 'Schlagzeug', child: Text('Schlagzeug (inkl. Drums & Percussion)')),
                      DropdownMenuItem(value: 'Pauken', child: Text('Pauken (Timpani)')),
                      DropdownMenuItem(value: 'Mallets', child: Text('Mallets (Glockenspiel, Xylo etc.)')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _profile = _profile.copyWith(percussionInstrument: val);
                        });
                        _saveProfile();
                      }
                    },
                  ),
                ],
                const SizedBox(height: 14),

                // Default Start Category / Folder
                DropdownButtonFormField<String>(
                  key: ValueKey('cat_$_defaultCategory'),
                  initialValue: categoriesList.contains(_defaultCategory)
                      ? _defaultCategory
                      : 'Aktuelle Noten',
                  decoration: const InputDecoration(
                    labelText: 'Standard-Ordner beim Start',
                    prefixIcon: Icon(Icons.folder_special_rounded),
                    helperText: 'Standard: Aktuelle Noten (öffnet immer den zuletzt aktiven Ordner)',
                  ),
                  items: categoriesList.map((cat) {
                    return DropdownMenuItem(value: cat, child: Text(cat));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _defaultCategory = val;
                      });
                      widget.storageService.setDefaultCategory(val);
                      widget.storageService.setLastActiveCategory(val);
                    }
                  },
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
                if (_account.isConfigured)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.emerald.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.emerald.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: AppTheme.emerald, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Verbunden als: ${_account.username}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.emerald),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Server: ${_account.cleanServerUrl}',
                          style: const TextStyle(fontSize: 12, color: AppTheme.darkTextSecondary),
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
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                                onPressed: _isTestingConnection ? null : _startBrowserLoginFlow,
                                icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                                label: const Text('Im Browser neu anmelden', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
                            const SizedBox(width: 4),
                            IconButton(
                              style: IconButton.styleFrom(
                                backgroundColor: AppTheme.darkSurface,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: const BorderSide(color: AppTheme.rose),
                                ),
                              ),
                              icon: const Icon(Icons.logout_rounded, size: 18, color: AppTheme.rose),
                              tooltip: 'Nextcloud trennen / Abmelden',
                              onPressed: _logout,
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                else
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
                                'Nextcloud Browser-Login',
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

                if (_connectionTestResult != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
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
                ],

                const SizedBox(height: 14),

                // Manual Login (Dezent in ExpansionTile)
                Material(
                  color: AppTheme.darkSurface.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: AppTheme.darkBorder.withValues(alpha: 0.7)),
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      leading: const Icon(Icons.tune_rounded, size: 18, color: AppTheme.darkTextMuted),
                      title: const Text(
                        'Manuelle Zugangsdaten & WebDAV (Erweitert)',
                        style: TextStyle(fontSize: 13, color: AppTheme.darkTextSecondary, fontWeight: FontWeight.w500),
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        const Divider(color: AppTheme.darkBorder, height: 1),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _serverUrlController,
                          decoration: const InputDecoration(
                            labelText: 'Server-URL',
                            hintText: 'https://cloud.mein-orchester.de',
                            prefixIcon: Icon(Icons.link_rounded),
                          ),
                          onChanged: (_) => _saveAccount(),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: 'Benutzername / E-Mail',
                            prefixIcon: Icon(Icons.account_circle_rounded),
                          ),
                          onChanged: (_) => _saveAccount(),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Passwort / App-Token',
                            prefixIcon: Icon(Icons.lock_rounded),
                          ),
                          onChanged: (_) => _saveAccount(),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _rootFolderController,
                          decoration: const InputDecoration(
                            labelText: 'Notenordner',
                            hintText: '/Noten',
                            prefixIcon: Icon(Icons.folder_rounded),
                          ),
                          onChanged: (_) => _saveAccount(),
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _isTestingConnection ? null : _testConnection,
                          icon: _isTestingConnection
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.wifi_tethering_rounded, size: 18),
                          label: const Text('Verbindung testen & speichern', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
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
                        color: AppTheme.amber.withValues(alpha: 0.12),
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
          const SizedBox(height: 16),

          // App Updates & ADB Pixel Fast-Installer Card
          Material(
            color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
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
                        child: const Icon(Icons.system_update_rounded, color: AppTheme.primaryLight, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'App-Updates & APK',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              'Installierte Version: v$_installedVersion',
                              style: const TextStyle(fontSize: 12, color: AppTheme.darkTextMuted),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _isCheckingUpdate || _isDownloadingUpdate ? null : _checkForUpdate,
                        icon: _isCheckingUpdate
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Prüfen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),

                  // If update is available or checked
                  if (_updateInfo != null && _updateInfo!.hasUpdate) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.emerald.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.emerald.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.new_releases_rounded, color: AppTheme.emerald, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Neue Version verfügbar: v${_updateInfo!.latestVersion}',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.emerald, fontSize: 14),
                              ),
                            ],
                          ),
                          if (_updateInfo!.releaseNotes.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              _updateInfo!.releaseNotes,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: AppTheme.darkTextSecondary),
                            ),
                          ],
                          const SizedBox(height: 12),
                          if (_isDownloadingUpdate) ...[
                            LinearProgressIndicator(
                              value: _downloadProgress > 0 ? _downloadProgress : null,
                              backgroundColor: Colors.white10,
                              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.emerald),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _downloadProgress > 0
                                  ? 'Herunterladen: ${(_downloadProgress * 100).toInt()}%'
                                  : 'Starte Download...',
                              style: const TextStyle(fontSize: 11, color: AppTheme.emerald),
                            ),
                          ] else ...[
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.emerald,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () => _downloadAndInstall(_updateInfo!.apkDownloadUrl),
                                    icon: const Icon(Icons.download_rounded, size: 16),
                                    label: const Text('APK direkt aktualisieren', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.primaryLight,
                                    side: const BorderSide(color: AppTheme.primaryLight),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: () {
                                    launchUrl(Uri.parse('https://github.com/Mindstorms123/notencloud/releases/latest'), mode: LaunchMode.externalApplication);
                                  },
                                  child: const Text('GitHub', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  if (_updateError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _updateError!,
                      style: const TextStyle(color: AppTheme.rose, fontSize: 12),
                    ),
                  ],

                  const SizedBox(height: 14),
                  const Divider(height: 1, color: Colors.white12),
                  const SizedBox(height: 14),

                  // ADB Fast Installer Tip
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkSurface : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.terminal_rounded, size: 20, color: AppTheme.amber),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Pixel Schnell-Installation (ADB)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.amber),
                              ),
                              SizedBox(height: 2),
                              Text(
                                './install_pixel.sh im Terminal ausführen',
                                style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.darkTextSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
