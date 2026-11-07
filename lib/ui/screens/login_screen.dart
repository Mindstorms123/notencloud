import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/nextcloud_account.dart';
import '../../services/nextcloud_service.dart';
import '../../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'main_navigation_screen.dart';

class LoginScreen extends StatefulWidget {
  final StorageService storageService;

  const LoginScreen({super.key, required this.storageService});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _serverUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _rootFolderController = TextEditingController(text: '/Noten');

  bool _isLoading = false;
  bool _isManualTesting = false;
  bool _showManualLogin = false;
  bool _obscurePassword = true;
  bool _clipboardDetected = false;
  String? _errorMessage;

  static const _defaultServerUrl = 'https://cloud.blasorchester-1862.de/';

  @override
  void initState() {
    super.initState();
    final savedAccount = widget.storageService.getAccount();
    if (savedAccount.serverUrl.isNotEmpty) {
      _serverUrlController.text = savedAccount.serverUrl;
    } else {
      _serverUrlController.text = _defaultServerUrl;
    }
    
    // Check initial deep link
    final initialRoute = WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    if (initialRoute.contains('notencloud://') || initialRoute.contains('server=')) {
      _parseAndApplyLinkOrText(initialRoute);
    }

    _checkClipboardForServerUrl();
  }

  void _parseAndApplyLinkOrText(String input) {
    var handled = false;
    // 1. Check for deep link URI: notencloud://setup?server=...&folder=...
    final uri = Uri.tryParse(input);
    if (uri != null && uri.scheme == 'notencloud') {
      final s = uri.queryParameters['server'];
      final f = uri.queryParameters['folder'];
      if (s != null && s.isNotEmpty) {
        _serverUrlController.text = s;
        handled = true;
      }
      if (f != null && f.isNotEmpty) {
        _rootFolderController.text = f;
        handled = true;
      }
    }

    // 2. Check for explicit Server: and Notenordner: text
    final serverMatch = RegExp(r'(?:server(?:\-url)?|adresse):\s*(https?://[^\s\n]+)', caseSensitive: false).firstMatch(input);
    if (serverMatch != null) {
      _serverUrlController.text = serverMatch.group(1)!.trim();
      handled = true;
    }

    final folderMatch = RegExp(r'(?:notenordner|ordner|folder):\s*(/[^\s\n]*)', caseSensitive: false).firstMatch(input);
    if (folderMatch != null) {
      _rootFolderController.text = folderMatch.group(1)!.trim();
      handled = true;
    }

    // 3. Fallback: Any http/https link with cloud/orchester/nextcloud
    if (!handled) {
      final urlMatch = RegExp(r'(https?://[^\s\n]+)').firstMatch(input);
      if (urlMatch != null) {
        final url = urlMatch.group(0)!.trim();
        if (url.contains('cloud') || url.contains('nextcloud') || url.contains('orchester') || url.contains('noten')) {
          _serverUrlController.text = url;
          handled = true;
        }
      }
    }

    if (handled && mounted) {
      setState(() {
        _clipboardDetected = true;
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

  Future<void> _checkClipboardForServerUrl() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text != null && text.isNotEmpty) {
        _parseAndApplyLinkOrText(text);
      }
    } catch (_) {}
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text != null && text.isNotEmpty) {
        _parseAndApplyLinkOrText(text);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppTheme.emerald,
              content: Text('Einrichtungs-Link aus Zwischenablage übernommen!'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (_) {}
  }

  void _shareSetupLink() {
    final rawUrl = _serverUrlController.text.trim();
    final serverUrl = rawUrl.isNotEmpty ? rawUrl : _defaultServerUrl;
    final folder = _rootFolderController.text.trim().isNotEmpty
        ? _rootFolderController.text.trim()
        : '/Noten';

    final setupLink = 'notencloud://setup?server=${Uri.encodeQueryComponent(serverUrl)}&folder=${Uri.encodeQueryComponent(folder)}';

    final shareText = '🎵 Blasorchester Notencloud Einrichtung:\n\n'
        'Tippe auf den Einrichtungs-Link, um Notencloud automatisch mit unserem Archiv zu verbinden:\n'
        '$setupLink\n\n'
        '(Alternativ: Server: $serverUrl | Notenordner: $folder)\n\n'
        'Anschließend in der App einfach auf "Im Browser anmelden" tippen – fertig!';

    Clipboard.setData(ClipboardData(text: setupLink));
    SharePlus.instance.share(ShareParams(text: shareText, subject: 'Notencloud Einrichtung'));
  }

  Future<void> _startBrowserLoginFlow() async {
    final rawUrl = _serverUrlController.text.trim();
    final serverUrl = rawUrl.isNotEmpty ? rawUrl : _defaultServerUrl;
    _serverUrlController.text = serverUrl;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final flow = await NextcloudService.initLoginFlow(serverUrl);
    if (flow == null) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Der Nextcloud-Server konnte unter dieser Adresse nicht erreicht werden. Bitte prüfe die Server-URL.';
      });
      return;
    }

    final loginUri = Uri.parse(flow.loginUrl);
    if (!await launchUrl(loginUri, mode: LaunchMode.externalApplication)) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Web-Browser konnte nicht automatisch geöffnet werden.';
      });
      return;
    }

    // Show waiting dialog with polling
    bool isCancelled = false;
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: AppTheme.darkCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(Icons.open_in_browser_rounded, color: AppTheme.primaryLight, size: 24),
              SizedBox(width: 12),
              Text(
                'Im Browser anmelden',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              const CircularProgressIndicator(color: AppTheme.primaryLight),
              const SizedBox(height: 20),
              const Text(
                'Dein Web-Browser wurde geöffnet.\n\nMelde dich wie gewohnt an und tippe anschließend auf "Zugriff gewähren".',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppTheme.darkTextSecondary, height: 1.4),
              ),
              const SizedBox(height: 12),
              Text(
                'Server: $serverUrl',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: AppTheme.darkTextMuted),
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
          Navigator.pop(context); // Close dialog
        }

        final folder = _rootFolderController.text.trim().isNotEmpty
            ? _rootFolderController.text.trim()
            : '/Noten';

        final account = NextcloudAccount(
          serverUrl: creds.server.isNotEmpty ? creds.server : serverUrl,
          username: creds.loginName,
          password: creds.appPassword,
          rootFolder: folder,
          isValidated: true,
        );

        await widget.storageService.saveAccount(account);
        unawaited(NextcloudService(account).ensureSetlistFolderExists());

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppTheme.emerald,
              content: Text('Erfolgreich als "${creds.loginName}" angemeldet!'),
            ),
          );

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => MainNavigationScreen(storageService: widget.storageService),
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
      _isLoading = false;
      if (!isCancelled) {
        _errorMessage = 'Zeitfenster für Bestätigung im Browser abgelaufen. Bitte erneut versuchen.';
      }
    });
  }

  Future<void> _manualLogin() async {
    final serverUrl = _serverUrlController.text.trim().isNotEmpty
        ? _serverUrlController.text.trim()
        : _defaultServerUrl;
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final folder = _rootFolderController.text.trim().isNotEmpty
        ? _rootFolderController.text.trim()
        : '/Noten';

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Bitte Benutzername und Passwort eingeben.';
      });
      return;
    }

    setState(() {
      _isManualTesting = true;
      _errorMessage = null;
    });

    final account = NextcloudAccount(
      serverUrl: serverUrl,
      username: username,
      password: password,
      rootFolder: folder,
    );

    final service = NextcloudService(account);
    final isConnected = await service.testConnection();

    if (isConnected) {
      await widget.storageService.saveAccount(account.copyWith(isValidated: true));
      unawaited(service.ensureSetlistFolderExists());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.emerald,
            content: Text('Erfolgreich als "$username" angemeldet!'),
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MainNavigationScreen(storageService: widget.storageService),
          ),
        );
      }
    } else {
      setState(() {
        _isManualTesting = false;
        _errorMessage = 'Verbindung fehlgeschlagen. Bitte Zugangsdaten und Server-Adresse prüfen.';
      });
    }
  }

  void _skipToOfflineMode() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MainNavigationScreen(storageService: widget.storageService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // App Branding Icon & Glow
                Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primary, AppTheme.emerald],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.35),
                        blurRadius: 28,
                        spreadRadius: 4,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.library_music_rounded,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                const Text(
                  'Notencloud',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                    color: AppTheme.darkTextPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Deine digitale Notenmappe fürs Blasorchester',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.darkTextSecondary,
                  ),
                ),
                const SizedBox(height: 28),

                // Main Login Card
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppTheme.darkBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Server URL input header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'ORCHESTER NEXTCLOUD',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                              color: AppTheme.primaryLight,
                            ),
                          ),
                          if (_clipboardDetected)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.emerald.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_rounded, color: AppTheme.emerald, size: 12),
                                  SizedBox(width: 4),
                                  Text(
                                    'Aus Zwischenablage',
                                    style: TextStyle(fontSize: 10, color: AppTheme.emerald, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Server URL Field
                      TextField(
                        controller: _serverUrlController,
                        keyboardType: TextInputType.url,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'https://cloud.mein-orchester.de',
                          prefixIcon: const Icon(Icons.dns_rounded, size: 20),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.content_paste_rounded, size: 18),
                                tooltip: 'Aus Zwischenablage einfügen',
                                onPressed: _pasteFromClipboard,
                              ),
                              IconButton(
                                icon: const Icon(Icons.share_rounded, size: 18),
                                tooltip: 'Einrichtungs-Link teilen',
                                onPressed: _shareSetupLink,
                              ),
                            ],
                          ),
                          helperText: 'Server-Adresse deiner Vereins-Nextcloud',
                          helperStyle: const TextStyle(fontSize: 11, color: AppTheme.darkTextMuted),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Primary Button: Im Browser anmelden
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [AppTheme.primary, Color(0xFF0EA5E9)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.35),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: _isLoading ? null : _startBrowserLoginFlow,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.open_in_browser_rounded, size: 22),
                          label: Text(
                            _isLoading ? 'Warte auf Bestätigung...' : 'Im Browser anmelden',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      const Text(
                        'Öffnet deine Nextcloud im Web-Browser. Einfach anmelden und auf "Zugriff gewähren" tippen.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: AppTheme.darkTextMuted, height: 1.3),
                      ),

                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.rose.withValues(alpha: 0.12),
                            border: Border.all(color: AppTheme.rose.withValues(alpha: 0.3)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: AppTheme.rose, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: AppTheme.rose, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Manual Login (Dezent / Ausklappbar)
                Material(
                  color: AppTheme.darkCard.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: AppTheme.darkBorder.withValues(alpha: 0.6)),
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      initiallyExpanded: _showManualLogin,
                      onExpansionChanged: (exp) => setState(() => _showManualLogin = exp),
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      leading: const Icon(Icons.tune_rounded, size: 18, color: AppTheme.darkTextMuted),
                      title: const Text(
                        'Manuelle Anmeldung (Passwort / Token)',
                        style: TextStyle(fontSize: 13, color: AppTheme.darkTextSecondary, fontWeight: FontWeight.w500),
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        const Divider(color: AppTheme.darkBorder, height: 1),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: 'Benutzername / E-Mail',
                            prefixIcon: Icon(Icons.account_circle_rounded, size: 20),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Passwort oder App-Token',
                            prefixIcon: const Icon(Icons.lock_rounded, size: 20),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                size: 18,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _rootFolderController,
                          decoration: const InputDecoration(
                            labelText: 'Notenordner',
                            hintText: '/Noten',
                            prefixIcon: Icon(Icons.folder_rounded, size: 20),
                          ),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            foregroundColor: AppTheme.primaryLight,
                            side: const BorderSide(color: AppTheme.primaryLight),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _isManualTesting ? null : _manualLogin,
                          icon: _isManualTesting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryLight),
                                )
                              : const Icon(Icons.login_rounded, size: 18),
                          label: Text(_isManualTesting ? 'Verbinde...' : 'Mit Passwort verbinden'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Offline-Skip Button
                TextButton(
                  onPressed: _skipToOfflineMode,
                  child: const Text(
                    'Ohne Cloud fortfahren (Offline-Modus)',
                    style: TextStyle(color: AppTheme.darkTextMuted, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
