import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

/// Detecta si la app se está ejecutando sobre Android TV / Google TV.
abstract final class DeviceProfile {
  static Future<bool> isAndroidTv() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final features = info.systemFeatures;
      if (features.isEmpty) return false;

      final declaresLeanback = features.any(
        (feature) =>
            feature.contains('android.software.leanback') ||
            feature.contains('android.hardware.type.television') ||
            feature.contains('android.software.live_tv'),
      );
      final hasTouchscreen = features.any(
        (feature) => feature.contains('android.hardware.touchscreen'),
      );

      return declaresLeanback || !hasTouchscreen;
    } catch (error) {
      debugPrint('No se pudo detectar Android TV: $error');
      return false;
    }
  }
}
