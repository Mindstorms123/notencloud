import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class AppUpdateInfo {
  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final String releaseName;
  final String releaseNotes;
  final String apkDownloadUrl;
  final int apkSizeBytes;
  final DateTime? publishedAt;

  const AppUpdateInfo({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseName,
    required this.releaseNotes,
    required this.apkDownloadUrl,
    this.apkSizeBytes = 0,
    this.publishedAt,
  });
}

class UpdateService {
  static const String githubRepo = 'Mindstorms123/notencloud';
  static const String releaseApiUrl = 'https://api.github.com/repos/$githubRepo/releases/latest';

  final http.Client _client;

  UpdateService([http.Client? client]) : _client = client ?? http.Client();

  /// Compares semantic versions (e.g. '1.0.1' > '1.0.0')
  static bool isNewerVersion(String latest, String current) {
    final cleanLatest = latest.replaceAll(RegExp(r'^[^\d]*'), '').trim();
    final cleanCurrent = current.replaceAll(RegExp(r'^[^\d]*'), '').trim();

    final latestParts = cleanLatest.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final currentParts = cleanCurrent.split('.').map((p) => int.tryParse(p) ?? 0).toList();

    while (latestParts.length < 3) {
      latestParts.add(0);
    }
    while (currentParts.length < 3) {
      currentParts.add(0);
    }

    for (int i = 0; i < 3; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
  }

  /// Checks GitHub Releases for a newer version
  Future<AppUpdateInfo> checkForUpdate() async {
    if (kIsWeb) {
      return const AppUpdateInfo(
        hasUpdate: false,
        currentVersion: 'Web PWA',
        latestVersion: 'Web PWA',
        releaseName: '',
        releaseNotes: '',
        apkDownloadUrl: '',
      );
    }
    String currentVersion = '1.0.0';
    try {
      final pkgInfo = await PackageInfo.fromPlatform();
      currentVersion = pkgInfo.version;
    } catch (_) {}

    try {
      final res = await _client.get(
        Uri.parse(releaseApiUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'Notencloud-App',
        },
      );

      if (res.statusCode != 200) {
        return AppUpdateInfo(
          hasUpdate: false,
          currentVersion: currentVersion,
          latestVersion: currentVersion,
          releaseName: '',
          releaseNotes: '',
          apkDownloadUrl: '',
        );
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final releaseName = data['name'] as String? ?? tagName;
      final releaseNotes = data['body'] as String? ?? '';
      final publishedAtStr = data['published_at'] as String?;
      final publishedAt = publishedAtStr != null ? DateTime.tryParse(publishedAtStr) : null;

      String apkUrl = '';
      int apkSize = 0;
      final assets = data['assets'] as List<dynamic>? ?? [];
      for (final a in assets) {
        final name = (a['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk')) {
          apkUrl = a['browser_download_url'] as String? ?? '';
          apkSize = a['size'] as int? ?? 0;
          break;
        }
      }

      final hasUpdate = isNewerVersion(tagName, currentVersion) && apkUrl.isNotEmpty;

      return AppUpdateInfo(
        hasUpdate: hasUpdate,
        currentVersion: currentVersion,
        latestVersion: tagName.replaceAll(RegExp(r'^[^\d]*'), ''),
        releaseName: releaseName,
        releaseNotes: releaseNotes,
        apkDownloadUrl: apkUrl,
        apkSizeBytes: apkSize,
        publishedAt: publishedAt,
      );
    } catch (e) {
      return AppUpdateInfo(
        hasUpdate: false,
        currentVersion: currentVersion,
        latestVersion: currentVersion,
        releaseName: '',
        releaseNotes: '',
        apkDownloadUrl: '',
      );
    }
  }

  /// Fortschritt des laufenden Update-Downloads (0–1), `null` wenn keiner läuft.
  ///
  /// Der Download hängt bewusst nicht an der Einstellungsseite: Er läuft
  /// weiter, wenn man in der App woandershin wechselt, und die Seite zeigt den
  /// Stand wieder an, sobald sie zurückkommt.
  static final ValueNotifier<double?> downloadProgress = ValueNotifier<double?>(null);
  static Future<OpenResult>? _activeDownload;

  /// Lädt die APK und startet die Installation. Ein zweiter Aufruf während
  /// eines laufenden Downloads hängt sich an diesen an.
  Future<OpenResult> downloadAndInstallApk(
    String apkUrl, {
    Function(double progress)? onProgress,
  }) {
    return _activeDownload ??= () async {
      downloadProgress.value = 0;
      try {
        final apkFile = await downloadApk(
          apkUrl,
          onProgress: (p) {
            downloadProgress.value = p;
            onProgress?.call(p);
          },
        );
        // Trigger Android package installer
        return await OpenFilex.open(
          apkFile.path,
          type: 'application/vnd.android.package-archive',
        );
      } finally {
        _activeDownload = null;
        downloadProgress.value = null;
      }
    }();
  }

  static bool _inForeground() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  /// Lädt die APK in den temporären Ordner.
  ///
  /// Geht das Handy aus oder wechselt man die App, trennt Android die
  /// Verbindung. Der Download bricht dann nicht ab, sondern wartet, bis die
  /// App wieder vorne ist, und setzt an der erreichten Stelle fort
  /// (HTTP-Range). Der Bildschirm bleibt währenddessen an.
  Future<File> downloadApk(
    String apkUrl, {
    Function(double progress)? onProgress,
    int maxAttempts = 6,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    final tempDir = await getTemporaryDirectory();
    final apkFile = File('${tempDir.path}/notencloud_update.apk');
    if (await apkFile.exists()) {
      await apkFile.delete();
    }

    var received = 0;
    var total = 0;
    var attempts = 0;
    var lastPercent = -1;

    try {
      await WakelockPlus.enable();
    } catch (_) {}

    try {
      while (true) {
        while (!_inForeground()) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        try {
          final req = http.Request('GET', Uri.parse(apkUrl));
          if (received > 0) req.headers['Range'] = 'bytes=$received-';
          final response = await _client.send(req);

          if (received > 0 && response.statusCode == 200) {
            // Der Server setzt nicht fort, sondern schickt alles neu.
            received = 0;
            total = 0;
          } else if (response.statusCode != 200 && response.statusCode != 206) {
            throw Exception('Download fehlgeschlagen (HTTP ${response.statusCode})');
          }
          if (total == 0) total = (response.contentLength ?? 0) + received;

          final sink = apkFile.openWrite(mode: received > 0 ? FileMode.append : FileMode.write);
          try {
            await for (final chunk in response.stream) {
              sink.add(chunk);
              received += chunk.length;
              // Nur bei jedem vollen Prozent melden: Pro Sekunde kommen
              // hunderte Datenpakete an, und jede Meldung baut Oberfläche neu auf.
              if (total > 0 && onProgress != null) {
                final percent = (received * 100) ~/ total;
                if (percent != lastPercent) {
                  lastPercent = percent;
                  onProgress((percent / 100).clamp(0.0, 1.0));
                }
              }
            }
          } finally {
            await sink.flush();
            await sink.close();
          }

          if (total > 0 && received < total) {
            throw Exception('Verbindung vorzeitig beendet ($received von $total Bytes)');
          }
          return apkFile;
        } catch (_) {
          // Abbruch im Hintergrund zählt nicht als Fehlversuch.
          if (_inForeground()) attempts++;
          if (attempts >= maxAttempts) rethrow;
          await Future<void>.delayed(retryDelay);
        }
      }
    } finally {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
    }
  }
}
