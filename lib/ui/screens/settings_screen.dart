import 'package:flutter/material.dart';
import '../../models/musician_profile.dart';
import '../../models/nextcloud_account.dart';
import '../../services/nextcloud_service.dart';
import '../../services/storage_service.dart';

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

  void _showGuidelineDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guideline: Noten-Ordnerstruktur'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Damit die App automatisch deine Stimme findet, empfehlen wir folgendes Schema auf der Nextcloud:',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 12),
              Text(
                '1. Ordner pro Stück:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Nextcloud/Notenarchiv/\n'
                '├── _Setlisten/  (für Auftrittslisten)\n'
                '├── 001_Alte_Kameraden/\n'
                '│   ├── Partitur.pdf\n'
                '│   ├── Trompete_1_Bb.pdf\n'
                '│   ├── Trompete_2_Bb.pdf\n'
                '│   └── Posaune_1_C.pdf\n'
                '└── 002_Bohemian_Rhapsody/...',
                style: TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              SizedBox(height: 12),
              Text(
                '2. Benennung der Stimmen:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '[Instrument]_[Stimme]_[Stimmung].[pdf]\n'
                'Beispiele:\n'
                '• Trompete_1_Bb.pdf\n'
                '• Klarinette_2_Bb.pdf\n'
                '• Altsaxophon_1_Eb.pdf\n'
                '• Posaune_1_Bass.pdf\n'
                '• Trompete_1-2_Bb.pdf (Kombistimme)',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Verstanden'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen & Profil', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'Noten-Guideline ansehen',
            onPressed: _showGuidelineDialog,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Section 1: Musician Profile
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.person, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 8),
                      const Text(
                        'Dein Musiker-Profil',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Die App filtert das Notenarchiv automatisch nach diesem Instrument.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const Divider(height: 24),

                  // Instrument dropdown
                  DropdownButtonFormField<String>(
                    value: MusicianProfile.standardInstruments.contains(_profile.instrument)
                        ? _profile.instrument
                        : 'Trompete',
                    decoration: const InputDecoration(
                      labelText: 'Instrument',
                      border: OutlineInputBorder(),
                    ),
                    items: MusicianProfile.standardInstruments.map((inst) {
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
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      // Voice number (1. Stimme, 2. Stimme...)
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _profile.voiceNumber,
                          decoration: const InputDecoration(
                            labelText: 'Stimme',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem(value: 0, child: Text('Keine / Alle')),
                            const DropdownMenuItem(value: 1, child: Text('1. Stimme')),
                            const DropdownMenuItem(value: 2, child: Text('2. Stimme')),
                            const DropdownMenuItem(value: 3, child: Text('3. Stimme')),
                            const DropdownMenuItem(value: 4, child: Text('4. Stimme')),
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
                            labelText: 'Stimmung / Schlüssel',
                            border: OutlineInputBorder(),
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
          ),
          const SizedBox(height: 16),

          // Section 2: Nextcloud Account
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.cloud, color: Colors.blueAccent),
                      const SizedBox(width: 8),
                      const Text(
                        'Nextcloud-Verbindung',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Verbinde die App mit deiner Orchester-Cloud zum automatischen Synchronisieren.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const Divider(height: 24),

                  TextField(
                    controller: _serverUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Server-URL',
                      hintText: 'https://cloud.mein-orchester.de',
                      prefixIcon: Icon(Icons.link),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _saveAccount(),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Benutzername',
                      prefixIcon: Icon(Icons.account_circle),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _saveAccount(),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Passwort / App-Token',
                      prefixIcon: Icon(Icons.lock),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _saveAccount(),
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: _rootFolderController,
                    decoration: const InputDecoration(
                      labelText: 'Notenordner auf Cloud',
                      hintText: '/Notenarchiv',
                      prefixIcon: Icon(Icons.folder),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _saveAccount(),
                  ),
                  const SizedBox(height: 16),

                  if (_connectionTestResult != null)
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: _isConnectionSuccess ? Colors.green.shade50 : Colors.red.shade50,
                        border: Border.all(
                          color:
                              _isConnectionSuccess ? Colors.green.shade300 : Colors.red.shade300,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isConnectionSuccess ? Icons.check_circle : Icons.error,
                            color: _isConnectionSuccess ? Colors.green : Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _connectionTestResult!,
                              style: TextStyle(
                                color: _isConnectionSuccess
                                    ? Colors.green.shade800
                                    : Colors.red.shade800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                    ),
                    onPressed: _isTestingConnection ? null : _testConnection,
                    icon: _isTestingConnection
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cable),
                    label: const Text('Verbindung testen & speichern'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Guideline info card
          Card(
            color: Colors.blue.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: const Icon(Icons.lightbulb_outline, color: Colors.blue),
              title: const Text('Noten-Ordner Guideline',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Erfahre, wie du deine Stücke für beste Erkennung sortierst.'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _showGuidelineDialog,
            ),
          ),
        ],
      ),
    );
  }
}
