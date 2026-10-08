// lib/services/alarm_policy.dart
//
// Reglas de decisión de las alarmas de ruta y del aviso push, sin Android ni
// Firebase de por medio para poder probarlas solas.

/// Datos que la app recuerda en el teléfono de la última cuenta que registró
/// para recibir avisos push. Viven en el almacenamiento del dispositivo, no
/// en memoria: sobreviven a que la app se cierre o se reinicie.
class DuenoPush {
  const DuenoPush({required this.choferId, required this.token});

  final String choferId;
  final String token;
}

/// Ids de alarmas que hay que cancelar.
///
/// [guardadas] son las que el sistema tiene programadas de verdad (leídas con
/// `Alarm.getAlarms()`), no las que esta ejecución de la app recuerda en
/// memoria: esa lista se pierde al reiniciar y entonces una alarma vieja nunca
/// se cancelaba aunque su ruta ya no existiera.
///
/// Una alarma que está sonando nunca se cancela aquí: solo el botón
/// "Detener" debe apagarla.
///
/// Con [soloAgregar] no se cancela nada. Se usa cuando llega el aviso de UNA
/// ruta: ese aviso no es la lista completa de hoy y no debe borrar las demás.
Set<int> idsACancelar({
  required Iterable<int> guardadas,
  required Iterable<int> deseadas,
  Iterable<int> sonando = const [],
  bool soloAgregar = false,
}) {
  if (soloAgregar) return <int>{};
  return guardadas
      .toSet()
      .difference(deseadas.toSet())
      .difference(sonando.toSet());
}

/// Si es seguro mandar al chofer a una pantalla de ajustes del sistema.
///
/// Nunca mientras suena una alarma: esas pantallas se encima sobre la app y
/// tapan el botón "Detener". Y solo una vez por ejecución, para no
/// interrumpirlo cada vez que vuelve a la app.
bool puedeAbrirAjustes({
  required bool yaSePidioEnEstaEjecucion,
  required bool hayAlarmaSonando,
}) => !hayAlarmaSonando && !yaSePidioEnEstaEjecucion;

/// Qué hacer con el registro de avisos push cuando una cuenta entra a este
/// teléfono.
enum AccionRegistroPush {
  /// Primera vez, o la misma cuenta de siempre: solo registrar.
  registrar,

  /// Antes lo usaba otra cuenta: darla de baja y luego registrar la nueva.
  /// Si no, los avisos de esa otra persona seguirían llegando aquí.
  darDeBajaAnteriorYRegistrar,
}

AccionRegistroPush decidirRegistro({
  required DuenoPush? guardado,
  required String choferNuevo,
}) {
  if (guardado == null) return AccionRegistroPush.registrar;
  if (guardado.choferId == choferNuevo) return AccionRegistroPush.registrar;
  return AccionRegistroPush.darDeBajaAnteriorYRegistrar;
}

/// Si un aviso push es para la cuenta que usa este teléfono ahora.
///
/// Si el aviso no dice a quién va (así son los del servidor de hoy) o la app
/// no sabe quién lo usa, se acepta. Si ambos datos existen y no coinciden, es
/// de otra persona y se ignora.
bool avisoEsParaEsteChofer({
  required String? choferDelAviso,
  required String? choferRegistrado,
}) {
  if (choferDelAviso == null || choferDelAviso.isEmpty) return true;
  if (choferRegistrado == null || choferRegistrado.isEmpty) return true;
  return choferDelAviso == choferRegistrado;
}
