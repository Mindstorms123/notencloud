import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notencloud/services/update_service.dart';

void main() {
  group('UpdateService Tests', () {
    test('isNewerVersion correctly compares semantic versions', () {
      expect(UpdateService.isNewerVersion('1.0.1', '1.0.0'), isTrue);
      expect(UpdateService.isNewerVersion('v1.1.0', '1.0.5'), isTrue);
      expect(UpdateService.isNewerVersion('v2.0.0', '1.9.9'), isTrue);
      expect(UpdateService.isNewerVersion('1.0.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('v1.0.0', '1.0.1'), isFalse);
      expect(UpdateService.isNewerVersion('0.9.5', '1.0.0'), isFalse);
    });

    test('checkForUpdate detects APK release from GitHub API', () async {
      final mockClient = MockClient((request) async {
        if (request.url.toString() == UpdateService.releaseApiUrl) {
          final payload = {
            'tag_name': 'v99.0.0',
            'name': 'v99.0.0 - Major Update',
            'body': 'Changelog: Neue Features hinzugefügt',
            'published_at': '2026-11-07T12:00:00Z',
            'assets': [
              {
                'name': 'app-release.apk',
                'size': 82194820,
                'browser_download_url': 'https://github.com/Mindstorms123/notencloud/releases/download/v99.0.0/app-release.apk',
              }
            ]
          };
          return http.Response(jsonEncode(payload), 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('Not Found', 404);
      });

      final service = UpdateService(mockClient);
      final updateInfo = await service.checkForUpdate();

      expect(updateInfo.hasUpdate, isTrue);
      expect(updateInfo.latestVersion, '99.0.0');
      expect(updateInfo.releaseName, 'v99.0.0 - Major Update');
      expect(updateInfo.apkDownloadUrl, contains('app-release.apk'));
      expect(updateInfo.apkSizeBytes, 82194820);
    });
  });
}
