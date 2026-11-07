import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

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

  /// Downloads the APK from GitHub and launches the Android package installer
  Future<OpenResult> downloadAndInstallApk(
    String apkUrl, {
    Function(double progress)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final apkFile = File('${tempDir.path}/notencloud_update.apk');

    if (await apkFile.exists()) {
      await apkFile.delete();
    }

    final req = http.Request('GET', Uri.parse(apkUrl));
    final streamedResponse = await _client.send(req);

    if (streamedResponse.statusCode != 200) {
      throw Exception('Download fehlgeschlagen (HTTP ${streamedResponse.statusCode})');
    }

    final totalBytes = streamedResponse.contentLength ?? 0;
    int receivedBytes = 0;

    final sink = apkFile.openWrite();
    await for (final chunk in streamedResponse.stream) {
      sink.add(chunk);
      receivedBytes += chunk.length;
      if (totalBytes > 0 && onProgress != null) {
        onProgress(receivedBytes / totalBytes);
      }
    }
    await sink.flush();
    await sink.close();

    // Trigger Android package installer
    return await OpenFilex.open(
      apkFile.path,
      type: 'application/vnd.android.package-archive',
    );
  }
}
