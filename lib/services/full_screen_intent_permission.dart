// lib/services/full_screen_intent_permission.dart
//
// En Android 14+ (API 34), el sistema exige un permiso especial —aparte
// del de notificaciones— para que una app pueda tomar toda la pantalla
// automáticamente, como hace un despertador o una llamada entrante. Sin
// él, la alarma de ruta llega solo como una notificación normal, fácil de
// perder entre las demás. No existe forma de auto-otorgarlo ni un diálogo
// estándar para pedirlo: solo se puede mandar al usuario a la pantalla de
// ajustes donde lo activa con un toque (ver MainActivity nativo).

import 'dart:io';

import 'package:flutter/services.dart';

class FullScreenIntentPermission {
  static const _channel = MethodChannel('taxicab/full_screen_intent');

  static Future<bool> isGranted() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('canUseFullScreenIntent') ??
          true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> openSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openFullScreenIntentSettings');
    } catch (_) {}
  }
}
