// lib/services/push_owner_store.dart
//
// Guarda en el teléfono a quién se registró por última vez para recibir los
// avisos push de ruta. Antes esto vivía solo en variables de la pantalla y se
// perdía al reiniciar la app, así que ya no se sabía a quién dar de baja al
// cerrar sesión o al entrar otra persona.

import 'package:shared_preferences/shared_preferences.dart';

import 'alarm_policy.dart';

class PushOwnerStore {
  static const _kChofer = 'push_dueno_chofer_id';
  static const _kToken = 'push_dueno_token';

  Future<DuenoPush?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final chofer = prefs.getString(_kChofer);
      final token = prefs.getString(_kToken);
      if (chofer == null || chofer.isEmpty || token == null || token.isEmpty) {
        return null;
      }
      return DuenoPush(choferId: chofer, token: token);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(DuenoPush dueno) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kChofer, dueno.choferId);
      await prefs.setString(_kToken, dueno.token);
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kChofer);
      await prefs.remove(_kToken);
    } catch (_) {}
  }
}
