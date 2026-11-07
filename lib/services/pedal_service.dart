import 'package:flutter/services.dart';

class ConnectedDevice {
  final int id;
  final String name;
  final int vendorId;
  final int productId;
  final bool isExternal;
  final bool isKeyboard;

  const ConnectedDevice({
    required this.id,
    required this.name,
    required this.vendorId,
    required this.productId,
    required this.isExternal,
    required this.isKeyboard,
  });

  factory ConnectedDevice.fromMap(Map<dynamic, dynamic> map) {
    return ConnectedDevice(
      id: map['id'] as int? ?? 0,
      name: map['name'] as String? ?? 'Unbekanntes Gerät',
      vendorId: map['vendorId'] as int? ?? 0,
      productId: map['productId'] as int? ?? 0,
      isExternal: map['isExternal'] as bool? ?? false,
      isKeyboard: map['isKeyboard'] as bool? ?? false,
    );
  }
}

class PedalService {
  static const MethodChannel _channel = MethodChannel('de.notenapp.notencloud/pedal');

  /// Fetches physical and external Bluetooth input devices currently recognized by Android
  static Future<List<ConnectedDevice>> getConnectedDevices() async {
    try {
      final List<dynamic>? raw = await _channel.invokeMethod('getConnectedInputDevices');
      if (raw == null) return [];
      return raw.map((e) => ConnectedDevice.fromMap(e as Map<dynamic, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Opens the system Bluetooth settings so the user can easily pair a new pedal
  static Future<bool> openBluetoothSettings() async {
    try {
      final res = await _channel.invokeMethod('openBluetoothSettings');
      return res == true;
    } catch (_) {
      return false;
    }
  }
}
