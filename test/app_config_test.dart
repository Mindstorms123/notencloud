import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notencloud/services/app_config.dart';
import 'package:notencloud/services/konzertmeister_service.dart';
import 'package:notencloud/services/nextcloud_service.dart';
import 'package:notencloud/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(AppConfig.reset);
  tearDown(AppConfig.reset);

  test('ohne config.json gelten die eingebauten Werte', () async {
    await AppConfig.load(isWeb: true, client: MockClient((_) async => http.Response('nicht da', 404)));
    expect(AppConfig.serverUrl, AppConfig.builtInServerUrl);
    expect(AppConfig.clubName, 'Blasorchester 1862');
    expect(AppConfig.konzertmeisterUrl, AppConfig.builtInKonzertmeisterUrl);
    expect(NextcloudService.proxyUrl, 'proxy.php');
  });

  test('config.json eines anderen Vereins wird übernommen', () async {
    late Uri requested;
    final client = MockClient((request) async {
      requested = request.url;
      return http.Response.bytes(
        utf8.encode(jsonEncode({
          'club': 'Musikverein Überlingen',
          'server': 'https://nx12345.your-storageshare.de',
          'folder': 'Notenarchiv',
          'konzertmeister': '',
        })),
        200,
      );
    });
    await AppConfig.load(isWeb: true, client: client);

    expect(requested.path, endsWith('config.json'));
    expect(AppConfig.clubName, 'Musikverein Überlingen');
    expect(AppConfig.serverUrl, 'https://nx12345.your-storageshare.de');
    expect(AppConfig.rootFolder, '/Notenarchiv');
    expect(KonzertmeisterService.defaultUrl, isEmpty);
  });

  test('fremder Verein ohne Kalender-Angabe bekommt nicht den eingebauten Kalender', () async {
    AppConfig.apply({'server': 'https://cloud.anderer-verein.de'});
    expect(AppConfig.konzertmeisterUrl, isEmpty);

    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    expect(storage.isKonzertmeisterEnabled(), isFalse);
    expect(storage.getKonzertmeisterUrl(), isEmpty);
  });

  test('eigener Kalender-Link und Proxy-Adresse aus config.json', () {
    AppConfig.apply({
      'server': 'https://cloud.anderer-verein.de',
      'konzertmeister': 'https://rest.konzertmeister.app/api/v3/org/X/upcomingappointments',
      'proxy': 'https://anderer-verein.de/notencloud/proxy.php',
    });
    expect(KonzertmeisterService.defaultUrl, contains('/org/X/'));
    final proxied = NextcloudService.resolveUrl(Uri.parse('https://cloud.anderer-verein.de/status.php'));
    expect(NextcloudService.proxyUrl, 'https://anderer-verein.de/notencloud/proxy.php');
    expect(proxied.toString(), anyOf(startsWith('https://anderer-verein.de/notencloud/proxy.php?url='), 'https://cloud.anderer-verein.de/status.php'));
  });

  test('kaputte oder unerreichbare config.json stört den Start nicht', () async {
    await AppConfig.load(isWeb: true, client: MockClient((_) async => http.Response('<html>', 200)));
    await AppConfig.load(isWeb: true, client: MockClient((_) async => throw Exception('offline')));
    await AppConfig.load(isWeb: false, client: MockClient((_) async => fail('außerhalb des Browsers nicht laden')));
    expect(AppConfig.serverUrl, AppConfig.builtInServerUrl);
  });
}
