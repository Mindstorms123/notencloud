import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Vereins-Einstellungen der App.
///
/// Die Web-Fassung liest sie beim Start aus der Datei `config.json`, die neben
/// der App auf dem Webhosting liegt (legt `install.php` an). So läuft dieselbe
/// fertig gebaute Web-App bei jedem Verein – ohne eigenen Build.
///
/// ```json
/// {
///   "club": "Musikverein Beispiel",
///   "server": "https://nx12345.your-storageshare.de",
///   "folder": "/Noten",
///   "konzertmeister": "",
///   "proxy": "proxy.php"
/// }
/// ```
///
/// Fehlt die Datei (oder ein Feld), gelten die eingebauten Werte.
class AppConfig {
  static const String builtInServerUrl = 'https://cloud.blasorchester-1862.de/';
  static const String builtInRootFolder = '/Noten';
  static const String builtInClubName = 'Blasorchester 1862';
  static const String builtInKonzertmeisterUrl =
      'https://rest.konzertmeister.app/api/v3/org/OALS_97300be2-6785-4047-b6f7-69d78c27a97b/upcomingappointments?showDescription=false&onlyPublicsite=true&limit=5&display=light&lang=de&hash=178e1a86f7a4f47ac79d26cbf617077cbe8308753d35cd6496c0e6d9e88d4543';

  /// Adresse des CORS-Proxys, falls beim Bauen festgelegt
  /// (`--dart-define=NOTENCLOUD_PROXY_URL=…`, z. B. für GitHub Pages).
  static const String _buildProxyUrl = String.fromEnvironment(
    'NOTENCLOUD_PROXY_URL',
    defaultValue: 'proxy.php',
  );

  /// Vorbelegte Nextcloud-Adresse im Anmeldebildschirm.
  static String serverUrl = builtInServerUrl;

  /// Vorbelegter Notenordner.
  static String rootFolder = builtInRootFolder;

  /// Vereinsname für PDF-Köpfe und Einladungstexte.
  static String clubName = builtInClubName;

  /// Vorbelegter Konzertmeister-Link; leer = Kalender zunächst aus.
  static String konzertmeisterUrl = builtInKonzertmeisterUrl;

  /// CORS-Proxy der Web-Fassung.
  static String proxyUrl = _buildProxyUrl;

  /// Setzt alles auf die eingebauten Werte zurück (für Tests).
  static void reset() {
    serverUrl = builtInServerUrl;
    rootFolder = builtInRootFolder;
    clubName = builtInClubName;
    konzertmeisterUrl = builtInKonzertmeisterUrl;
    proxyUrl = _buildProxyUrl;
  }

  /// Übernimmt die Felder einer `config.json`.
  static void apply(Map<String, dynamic> json) {
    String? text(String key) {
      final value = json[key];
      return value is String ? value.trim() : null;
    }

    final server = text('server');
    if (server != null && server.isNotEmpty) {
      serverUrl = server;
      // Ein anderer Verein: Der eingebaute Kalender gehört nicht dazu.
      if (_host(server) != _host(builtInServerUrl)) {
        konzertmeisterUrl = '';
      }
    }
    final folder = text('folder');
    if (folder != null && folder.isNotEmpty) {
      rootFolder = folder.startsWith('/') ? folder : '/$folder';
    }
    final club = text('club');
    if (club != null && club.isNotEmpty) clubName = club;
    final km = text('konzertmeister');
    if (km != null) konzertmeisterUrl = km;
    final proxy = text('proxy');
    if (proxy != null && proxy.isNotEmpty) proxyUrl = proxy;
  }

  static String _host(String url) => Uri.tryParse(url)?.host.toLowerCase() ?? '';

  /// Lädt `config.json` neben der Web-App. Außerhalb des Browsers passiert
  /// nichts. Fehler (Datei fehlt, kein Netz) sind unkritisch.
  static Future<void> load({http.Client? client, bool? isWeb}) async {
    if (!(isWeb ?? kIsWeb)) return;
    final c = client ?? http.Client();
    try {
      final response = await c
          .get(Uri.base.resolve('config.json'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) apply(decoded);
    } catch (_) {
      // Eingebaute Werte bleiben.
    } finally {
      if (client == null) c.close();
    }
  }
}
