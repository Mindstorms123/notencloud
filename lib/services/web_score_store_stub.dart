import 'dart:typed_data';

/// Platzhalter außerhalb des Browsers: Dort liegen Noten als Dateien.
class WebScoreStore {
  Future<Set<String>> keys() async => {};
  Future<Uint8List?> read(String key) async => null;
  Future<void> write(String key, Uint8List bytes) async {}
}
