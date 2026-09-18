// lib/services/battery_optimization_permission.dart
//
// Android puede poner esta app en un modo de ahorro de batería agresivo
// después de un rato en segundo plano, lo que le impide despertar para
// programar la alarma de ruta cuando llega el aviso del servidor. Pedir
// que se ignore la optimización de batería para esta app mejora bastante
// esa probabilidad. Requiere mandar al usuario a un diálogo del sistema;
// no se puede auto-otorgar.

import 'dart:io';

import 'package:flutter/services.dart';

class BatteryOptimizationPermission {
  static const _channel = MethodChannel('taxicab/battery_optimization');

  static Future<bool> isIgnoring() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>(
              'isIgnoringBatteryOptimizations') ??
          true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> requestIgnore() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }
}
