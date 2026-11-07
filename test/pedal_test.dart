import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notencloud/models/pedal_settings.dart';
import 'package:notencloud/services/pedal_service.dart';
import 'package:notencloud/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PedalSettings Tests', () {
    test('Default settings are enabled in universal mode', () {
      final settings = PedalSettings.defaultSettings();
      expect(settings.enabled, isTrue);
      expect(settings.mode, PedalMode.universal);
      expect(settings.setlistAutoAdvance, isTrue);
      expect(settings.setlistAutoRewind, isFalse);
    });

    test('Universal mode recognizes standard page turn keys', () {
      const settings = PedalSettings(enabled: true, mode: PedalMode.universal);

      // Next page keys
      expect(settings.isNextKey(LogicalKeyboardKey.pageDown), isTrue);
      expect(settings.isNextKey(LogicalKeyboardKey.arrowDown), isTrue);
      expect(settings.isNextKey(LogicalKeyboardKey.arrowRight), isTrue);
      expect(settings.isNextKey(LogicalKeyboardKey.space), isTrue);
      expect(settings.isNextKey(LogicalKeyboardKey.enter), isTrue);

      // Prev page keys
      expect(settings.isPrevKey(LogicalKeyboardKey.pageUp), isTrue);
      expect(settings.isPrevKey(LogicalKeyboardKey.arrowUp), isTrue);
      expect(settings.isPrevKey(LogicalKeyboardKey.arrowLeft), isTrue);
      expect(settings.isPrevKey(LogicalKeyboardKey.backspace), isTrue);

      // Unrelated keys
      expect(settings.isNextKey(LogicalKeyboardKey.keyA), isFalse);
      expect(settings.isPrevKey(LogicalKeyboardKey.keyZ), isFalse);
    });

    test('PageUpDown mode strictly filters to PageUp and PageDown', () {
      const settings = PedalSettings(enabled: true, mode: PedalMode.pageUpDown);

      expect(settings.isNextKey(LogicalKeyboardKey.pageDown), isTrue);
      expect(settings.isPrevKey(LogicalKeyboardKey.pageUp), isTrue);

      expect(settings.isNextKey(LogicalKeyboardKey.arrowDown), isFalse);
      expect(settings.isPrevKey(LogicalKeyboardKey.arrowUp), isFalse);
    });

    test('ArrowKeys mode strictly filters to arrow keys', () {
      const settings = PedalSettings(enabled: true, mode: PedalMode.arrowKeys);

      expect(settings.isNextKey(LogicalKeyboardKey.arrowDown), isTrue);
      expect(settings.isNextKey(LogicalKeyboardKey.arrowRight), isTrue);
      expect(settings.isPrevKey(LogicalKeyboardKey.arrowUp), isTrue);
      expect(settings.isPrevKey(LogicalKeyboardKey.arrowLeft), isTrue);

      expect(settings.isNextKey(LogicalKeyboardKey.pageDown), isFalse);
      expect(settings.isPrevKey(LogicalKeyboardKey.pageUp), isFalse);
    });

    test('Custom mode checks learned key codes', () {
      final settings = PedalSettings(
        enabled: true,
        mode: PedalMode.custom,
        customNextKeyId: LogicalKeyboardKey.keyF.keyId,
        customNextKeyLabel: 'F',
        customPrevKeyId: LogicalKeyboardKey.keyB.keyId,
        customPrevKeyLabel: 'B',
      );

      expect(settings.isNextKey(LogicalKeyboardKey.keyF), isTrue);
      expect(settings.isPrevKey(LogicalKeyboardKey.keyB), isTrue);

      expect(settings.isNextKey(LogicalKeyboardKey.pageDown), isFalse);
      expect(settings.isPrevKey(LogicalKeyboardKey.pageUp), isFalse);
    });

    test('Disabled pedal ignores all keys', () {
      const settings = PedalSettings(enabled: false, mode: PedalMode.universal);

      expect(settings.isNextKey(LogicalKeyboardKey.pageDown), isFalse);
      expect(settings.isPrevKey(LogicalKeyboardKey.pageUp), isFalse);
    });

    test('Serialization and deserialization in StorageService works correctly', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = await StorageService.init();

      // Default
      final initial = storage.getPedalSettings();
      expect(initial.enabled, isTrue);

      // Save updated
      final updated = initial.copyWith(
        enabled: false,
        mode: PedalMode.arrowKeys,
        setlistAutoAdvance: false,
        setlistAutoRewind: true,
        selectedDeviceName: 'PageFlip Firefly',
      );
      await storage.savePedalSettings(updated);

      final loaded = storage.getPedalSettings();
      expect(loaded.enabled, isFalse);
      expect(loaded.mode, PedalMode.arrowKeys);
      expect(loaded.setlistAutoAdvance, isFalse);
      expect(loaded.setlistAutoRewind, isTrue);
      expect(loaded.selectedDeviceName, 'PageFlip Firefly');

      // Clear device back to null (Alle Pedale)
      final cleared = loaded.copyWith(clearSelectedDevice: true);
      expect(cleared.selectedDeviceName, isNull);
      await storage.savePedalSettings(cleared);
      final reloaded = storage.getPedalSettings();
      expect(reloaded.selectedDeviceName, isNull);
    });

    test('ConnectedDevice deserializes from map correctly', () {
      final dev = ConnectedDevice.fromMap({
        'id': 3,
        'name': 'AirTurn DUO 500',
        'vendorId': 0x1234,
        'productId': 0x5678,
        'isExternal': true,
        'isKeyboard': true,
      });

      expect(dev.id, 3);
      expect(dev.name, 'AirTurn DUO 500');
      expect(dev.isExternal, isTrue);
      expect(dev.isKeyboard, isTrue);
    });
  });
}
