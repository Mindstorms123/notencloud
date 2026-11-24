@TestOn('browser')
library;

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:notencloud/services/storage_service.dart';
import 'package:notencloud/services/web_score_store_web.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('scores survive a restart of the web app', () async {
    final store = WebScoreStore();
    const key = '01_Aktuelle Noten_Böhmischer Traum_Flügelhorn 1 in Bb.pdf';
    final bytes = Uint8List.fromList(List.generate(5000, (i) => i % 251));

    await store.write(key, bytes);
    expect(await store.keys(), contains(key));
    expect(await store.read(key), bytes);
    expect(await store.read('gibt es nicht'), isNull);
  });

  test('StorageService finds persisted scores after a fresh start', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await StorageService.init();
    final bytes = Uint8List.fromList([37, 80, 68, 70, 1, 2, 3]);
    first.cachePartBytes('Song A', 'Tuba 1.pdf', bytes);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // Neustart: neuer Dienst, leerer Arbeitsspeicher.
    final second = await StorageService.init();
    expect(second.getCachedPartBytes('Song A', 'Tuba 1.pdf'), isNull);
    expect(second.hasCachedPartBytes('Song A', 'Tuba 1.pdf'), isTrue);
    expect(await second.isPartDownloaded('Song A', 'Tuba 1.pdf'), isTrue);
    expect(await second.loadPartBytes('Song A', 'Tuba 1.pdf'), bytes);
    expect(await second.loadPartBytes('Song B', 'Tuba 1.pdf'), isNull);
  });
}
