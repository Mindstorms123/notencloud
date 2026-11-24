import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// Dauerhafte Ablage heruntergeladener Noten in der Web-App.
///
/// Nutzt den Cache-Speicher des Browsers, damit die Noten einen Neustart
/// überstehen und auf der Bühne ohne Internet verfügbar sind.
class WebScoreStore {
  static const _cacheName = 'notencloud-scores-v1';
  static const _prefix = '/__notencloud_scores/';

  static String _url(String key) => '$_prefix${Uri.encodeComponent(key)}';

  Future<web.Cache> _open() => web.window.caches.open(_cacheName).toDart;

  Future<Set<String>> keys() async {
    final cache = await _open();
    final requests = (await cache.keys().toDart).toDart;
    final result = <String>{};
    for (final request in requests) {
      final path = Uri.parse(request.url).path;
      final index = path.indexOf(_prefix);
      if (index < 0) continue;
      result.add(Uri.decodeComponent(path.substring(index + _prefix.length)));
    }
    return result;
  }

  Future<Uint8List?> read(String key) async {
    final cache = await _open();
    final response = await cache.match(_url(key).toJS).toDart;
    if (response == null) return null;
    final buffer = await response.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }

  Future<void> write(String key, Uint8List bytes) async {
    final cache = await _open();
    final headers = web.Headers()..set('Content-Type', 'application/pdf');
    final response = web.Response(bytes.toJS, web.ResponseInit(headers: headers));
    await cache.put(_url(key).toJS, response).toDart;
  }
}
