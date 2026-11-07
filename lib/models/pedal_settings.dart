import 'package:flutter/services.dart';

enum PedalMode {
  universal,   // PageUp/Down, Arrows, Space, Enter (Standard)
  pageUpDown,  // Nur Bild auf / Bild ab
  arrowKeys,   // Nur Pfeiltasten (Hoch/Runter, Links/Rechts)
  spaceEnter,  // Leertaste / Enter
  custom,      // Benutzerdefinierte Tastenbelegung
}

class PedalSettings {
  final bool enabled;
  final PedalMode mode;
  final int? customNextKeyId;
  final String? customNextKeyLabel;
  final int? customPrevKeyId;
  final String? customPrevKeyLabel;
  final bool setlistAutoAdvance;
  final bool setlistAutoRewind;
  final String? selectedDeviceName;

  const PedalSettings({
    this.enabled = true,
    this.mode = PedalMode.universal,
    this.customNextKeyId,
    this.customNextKeyLabel,
    this.customPrevKeyId,
    this.customPrevKeyLabel,
    this.setlistAutoAdvance = true,
    this.setlistAutoRewind = false,
    this.selectedDeviceName,
  });

  bool isNextKey(LogicalKeyboardKey key) {
    if (!enabled) return false;
    switch (mode) {
      case PedalMode.universal:
        return key == LogicalKeyboardKey.pageDown ||
            key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.space ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter;
      case PedalMode.pageUpDown:
        return key == LogicalKeyboardKey.pageDown;
      case PedalMode.arrowKeys:
        return key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowRight;
      case PedalMode.spaceEnter:
        return key == LogicalKeyboardKey.space ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter;
      case PedalMode.custom:
        return customNextKeyId != null && key.keyId == customNextKeyId;
    }
  }

  bool isPrevKey(LogicalKeyboardKey key) {
    if (!enabled) return false;
    switch (mode) {
      case PedalMode.universal:
        return key == LogicalKeyboardKey.pageUp ||
            key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.backspace;
      case PedalMode.pageUpDown:
        return key == LogicalKeyboardKey.pageUp;
      case PedalMode.arrowKeys:
        return key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowLeft;
      case PedalMode.spaceEnter:
        return key == LogicalKeyboardKey.pageUp ||
            key == LogicalKeyboardKey.backspace;
      case PedalMode.custom:
        return customPrevKeyId != null && key.keyId == customPrevKeyId;
    }
  }

  PedalSettings copyWith({
    bool? enabled,
    PedalMode? mode,
    int? customNextKeyId,
    String? customNextKeyLabel,
    int? customPrevKeyId,
    String? customPrevKeyLabel,
    bool? setlistAutoAdvance,
    bool? setlistAutoRewind,
    String? selectedDeviceName,
    bool clearSelectedDevice = false,
  }) {
    return PedalSettings(
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
      customNextKeyId: customNextKeyId ?? this.customNextKeyId,
      customNextKeyLabel: customNextKeyLabel ?? this.customNextKeyLabel,
      customPrevKeyId: customPrevKeyId ?? this.customPrevKeyId,
      customPrevKeyLabel: customPrevKeyLabel ?? this.customPrevKeyLabel,
      setlistAutoAdvance: setlistAutoAdvance ?? this.setlistAutoAdvance,
      setlistAutoRewind: setlistAutoRewind ?? this.setlistAutoRewind,
      selectedDeviceName: clearSelectedDevice ? null : (selectedDeviceName ?? this.selectedDeviceName),
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'mode': mode.name,
    'customNextKeyId': customNextKeyId,
    'customNextKeyLabel': customNextKeyLabel,
    'customPrevKeyId': customPrevKeyId,
    'customPrevKeyLabel': customPrevKeyLabel,
    'setlistAutoAdvance': setlistAutoAdvance,
    'setlistAutoRewind': setlistAutoRewind,
    'selectedDeviceName': selectedDeviceName,
  };

  factory PedalSettings.fromJson(Map<String, dynamic> json) {
    return PedalSettings(
      enabled: json['enabled'] as bool? ?? true,
      mode: PedalMode.values.firstWhere(
        (m) => m.name == json['mode'],
        orElse: () => PedalMode.universal,
      ),
      customNextKeyId: json['customNextKeyId'] as int?,
      customNextKeyLabel: json['customNextKeyLabel'] as String?,
      customPrevKeyId: json['customPrevKeyId'] as int?,
      customPrevKeyLabel: json['customPrevKeyLabel'] as String?,
      setlistAutoAdvance: json['setlistAutoAdvance'] as bool? ?? true,
      setlistAutoRewind: json['setlistAutoRewind'] as bool? ?? false,
      selectedDeviceName: json['selectedDeviceName'] as String?,
    );
  }

  static PedalSettings defaultSettings() => const PedalSettings();
}
