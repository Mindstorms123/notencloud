import 'package:flutter_test/flutter_test.dart';
import 'package:notencloud/services/pedal_service.dart';

ConnectedDevice device(String name, {bool external = false}) => ConnectedDevice.fromMap({
      'id': 1,
      'name': name,
      'vendorId': 0,
      'productId': 0,
      'isExternal': external,
      'isKeyboard': true,
    });

void main() {
  test('built-in phone hardware is not offered as a pedal', () {
    for (final name in ['Virtual', 'gpio_keys', 'goodix_fingerprint', 'goodix_ts0', 'uinput-fpc', 'qpnp_pon']) {
      expect(PedalService.isExternalPedalCandidate(device(name)), isFalse, reason: name);
      // Auch dann nicht, wenn das Handy sie fälschlich als extern meldet.
      expect(PedalService.isExternalPedalCandidate(device(name, external: true)), isFalse, reason: name);
    }
  });

  test('bluetooth pedals and keyboards are still listed', () {
    for (final name in ['PageFlip Firefly', 'AirTurn DUO', 'BT-105', 'Donner Page Turner', 'Logitech K380']) {
      expect(PedalService.isExternalPedalCandidate(device(name, external: true)), isTrue, reason: name);
    }
  });
}
