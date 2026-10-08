// lib/services/route_alarm_service.dart
//
// Recibe las rutas de hoy del chofer (enviadas por la página web a través
// del canal JavaScript "TaxiCabNative", o por un push del servidor) y
// programa, por cada una:
//  - una **notificación local** 30 minutos antes del inicio (recordatorio:
//    "tu ruta es en 30 min, debes estar en el punto de inicio en 15"), y
//  - una **alarma** (sonido) 15 minutos antes del inicio.
//
// Ambas se programan en el propio dispositivo (no dependen de internet,
// APNS ni Cloud Functions una vez programadas), y suenan/aparecen aunque
// el celular esté bloqueado o la app en segundo plano. Solo Android.
//
// Programar la alarma completa (con pantalla propia y botón de detener)
// requiere que la app "despierte" un instante para ejecutar el código —
// algo que Android puede negarse a hacer si la app lleva un rato en
// segundo plano (ahorro de batería agresivo). Como respaldo, el servidor
// manda un SEGUNDO push justo a los 15 min usando un canal de
// notificación con sonido de alarma propio (`_hardAlarmChannelId`): ese
// push lo muestra Android directamente sin necesitar que la app despierte,
// así que siempre llega algo aunque la alarma completa no logre sonar.

import 'dart:io';

import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'alarm_policy.dart';
import 'battery_optimization_permission.dart';
import 'full_screen_intent_permission.dart';

class RouteAlarmService {
  static final RouteAlarmService _instance = RouteAlarmService._internal();
  factory RouteAlarmService() => _instance;
  RouteAlarmService._internal();

  static const Duration alarmLead = Duration(minutes: 15);
  static const Duration notificationLead = Duration(minutes: 30);
  static const String _timeZone = 'America/Monterrey';

  static const _cancelledStates = {
    'cancelado',
    'cancelado_sin_cobro',
    'cancelado_con_cobro',
    'rechazada',
    'rechazado',
  };

  /// La alarma es solo para avisar que el chofer va tarde a su punto de
  /// inicio. Si ya confirmó su llegada (o la ruta ya avanzó más allá),
  /// dejarla sonar ya no tiene sentido.
  static const _alreadyStartedStates = {
    'punto_inicio',
    'en_proceso',
    'en_progreso',
    'inicio',
    'completada',
    'completado',
    'finalizado',
  };

  static const _androidChannelId = 'chofer_route_reminders';

  /// Canal usado por el push de respaldo que manda el servidor a los 15
  /// min: sonido de alarma propio, máxima importancia. Debe existir
  /// ANTES de que llegue el push (Android ignora cambios de sonido en un
  /// canal ya creado), así que se crea aquí mismo en [init].
  static const hardAlarmChannelId = 'chofer_route_alarm_push';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  final Set<int> _scheduledAlarmIds = {};
  final Set<int> _scheduledNotificationIds = {};
  bool _initialized = false;

  /// Si en esta ejecución ya se mandó al chofer a pantallas de ajustes.
  bool _ajustesYaPedidos = false;
  tz.Location? _location;

  /// Inicializa el plugin de notificaciones locales y la base de zonas
  /// horarias. Idempotente (la parte cara, crear canales, solo corre una
  /// vez). Debe llamarse una vez al arrancar la app.
  ///
  /// [abrirAjustes] permite mandar al chofer a pantallas de ajustes del
  /// sistema para pedirle permisos especiales. Solo se hace una vez por
  /// ejecución y nunca mientras suena una alarma (ver [puedeAbrirAjustes]).
  /// El aviso push en segundo plano lo pasa en `false`: ahí no hay pantalla.
  Future<void> init({bool abrirAjustes = true}) async {
    if (kIsWeb) return;
    if (!_initialized) {
      _initialized = true;
      try {
        tzdata.initializeTimeZones();
        _location = tz.getLocation(_timeZone);

        const androidInit = AndroidInitializationSettings(
          '@mipmap/ic_launcher',
        );
        await _notifications.initialize(
          settings: const InitializationSettings(android: androidInit),
        );

        final androidImpl = _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        if (androidImpl != null) {
          await androidImpl.createNotificationChannel(
            const AndroidNotificationChannel(
              _androidChannelId,
              'Recordatorios de ruta',
              description: 'Aviso 30 minutos antes del inicio de cada ruta.',
              importance: Importance.high,
            ),
          );
          await androidImpl.createNotificationChannel(
            const AndroidNotificationChannel(
              hardAlarmChannelId,
              'Alarma de ruta (respaldo del servidor)',
              description:
                  'Aviso fuerte 15 minutos antes del inicio de la '
                  'ruta, por si la app no pudo programar la alarma completa.',
              importance: Importance.max,
              playSound: true,
              sound: RawResourceAndroidNotificationSound('route_alarm_sound'),
              enableVibration: true,
            ),
          );
        }
      } catch (e) {
        debugPrint('RouteAlarmService.init error: $e');
      }
    }
    await _ensurePermissions(abrirAjustes: abrirAjustes);
  }

  /// Se llama cada vez que el chofer vuelve a la app. Revisa los permisos
  /// normales, pero NO abre pantallas de ajustes: antes lo hacía en cada
  /// regreso, y si el chofer volvía a la app justo para apagar una alarma, le
  /// caía encima una pantalla de ajustes que tapaba el botón "Detener".
  Future<void> alVolverALaApp() async {
    if (kIsWeb) return;
    if (!_initialized) {
      await init();
      return;
    }
    await _ensurePermissions(abrirAjustes: false);
  }

  /// Revisa (y, si falta, vuelve a pedir) los permisos de los que depende
  /// que la alarma realmente se vea y suene. Los diálogos normales (notificaciones)
  /// se piden siempre que falten; las pantallas de ajustes del sistema solo si
  /// [abrirAjustes] y [puedeAbrirAjustes] lo permiten.
  Future<void> _ensurePermissions({required bool abrirAjustes}) async {
    try {
      final androidImpl = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      // Sin esto no aparece NI SIQUIERA la notificación con el botón
      // "Detener" — solo el sonido, sin nada visible para pararlo.
      await androidImpl?.requestNotificationsPermission();

      final abrir =
          abrirAjustes &&
          puedeAbrirAjustes(
            yaSePidioEnEstaEjecucion: _ajustesYaPedidos,
            hayAlarmaSonando: Alarm.ringing.value.alarms.isNotEmpty,
          );
      if (!abrir) return;
      _ajustesYaPedidos = true;

      // Android 12+ requiere este permiso especial (aparte del de
      // notificaciones) para que las alarmas/notificaciones programadas
      // suenen puntuales. Sin él, el sistema las descarta en silencio.
      final status = await Permission.scheduleExactAlarm.status;
      if (!status.isGranted) {
        await Permission.scheduleExactAlarm.request();
      }

      // Android 14+ además exige este otro permiso para que la alarma
      // pueda tomar toda la pantalla (como un despertador real) en vez de
      // mostrarse solo como una notificación normal. No hay diálogo
      // estándar: mandamos al usuario directo al ajuste correspondiente.
      if (!await FullScreenIntentPermission.isGranted()) {
        await FullScreenIntentPermission.openSettings();
      }

      // Pide que Android no ponga esta app en ahorro de batería agresivo,
      // para que el push de 30 min tenga más probabilidad de despertarla
      // y programar la alarma completa (no solo depender del respaldo).
      if (!await BatteryOptimizationPermission.isIgnoring()) {
        await BatteryOptimizationPermission.requestIgnore();
      }
    } catch (e) {
      debugPrint('RouteAlarmService._ensurePermissions error: $e');
    }
  }

  /// [routes] es una lista de mapas con: id (String), ruta (String),
  /// estado (String), dia ("YYYY-MM-DD"), hora ("HH:mm" o null).
  ///
  /// Con [soloAgregar] solo se programan las rutas recibidas y no se cancela
  /// nada más: es lo que se usa cuando llega el aviso push de UNA ruta, que no
  /// es la lista completa de hoy.
  Future<void> syncAlarms(
    List<Map<String, dynamic>> routes, {
    bool soloAgregar = false,
  }) async {
    if (kIsWeb) return;
    if (!_initialized) await init();

    debugPrint(
      '[RouteAlarmService] syncAlarms: ${routes.length} rutas recibidas',
    );

    final plan = planificar(routes, DateTime.now());

    debugPrint(
      '[RouteAlarmService] programando ${plan.alarmas.length} '
      'alarma(s) y ${plan.notificaciones.length} notificación(es)',
    );

    await _syncAlarmSet(plan.alarmas, soloAgregar: soloAgregar);
    await _syncNotificationSet(plan.notificaciones, soloAgregar: soloAgregar);
  }

  /// Qué alarmas y notificaciones corresponden a [routes] en el instante
  /// [now]. Es pura (no toca el sistema) para poder probarla.
  @visibleForTesting
  static ({Map<int, PlanRuta> alarmas, Map<int, PlanRuta> notificaciones})
  planificar(List<Map<String, dynamic>> routes, DateTime now) {
    final alarmas = <int, PlanRuta>{};
    final notificaciones = <int, PlanRuta>{};

    for (final route in routes) {
      final estado = (route['estado'] as String? ?? '').toLowerCase();
      if (_cancelledStates.contains(estado)) continue;
      if (_alreadyStartedStates.contains(estado)) continue;

      final start = _startDateTime(route);
      if (start == null) continue;

      final routeName = route['ruta'] as String? ?? 'tu ruta';
      final id = route['id'] as String? ?? '';
      if (id.isEmpty) continue;

      // Si la hora "normal" de la alarma (15 min antes) ya pasó pero la
      // ruta todavía no arranca, no la descartamos en silencio — suena
      // AHORA. Pasa, por ejemplo, cuando el push de respaldo de los 15
      // min es lo que finalmente logra despertar la app: para ese
      // entonces el instante "start - 15min" ya quedó unos segundos
      // atrás, y sin este ajuste la alarma completa (con pantalla y botón
      // de apagar) nunca se programaría — el chofer se quedaría solo con
      // el sonido de la notificación de respaldo, sin nada con qué
      // apagarla.
      final alarmTime = start.subtract(alarmLead);
      if (start.isAfter(now)) {
        final ringAt = alarmTime.isAfter(now) ? alarmTime : now;
        alarmas[_alarmId(id)] = PlanRuta(
          routeName: routeName,
          ring: ringAt,
          start: start,
        );
      }

      final notifTime = start.subtract(notificationLead);
      if (notifTime.isAfter(now)) {
        notificaciones[_notificationId(id)] = PlanRuta(
          routeName: routeName,
          ring: notifTime,
          start: start,
        );
      }
    }
    return (alarmas: alarmas, notificaciones: notificaciones);
  }

  Future<void> _syncAlarmSet(
    Map<int, PlanRuta> desired, {
    bool soloAgregar = false,
  }) async {
    // Una alarma cuya hora ya pasó no siempre es obsoleta: puede estar
    // sonando en este momento (su ventana ya se cumplió). No la toques —
    // solo el botón "Detener" o el propio paquete deben apagarla.
    final ringingIds = Alarm.ringing.value.alarms.map((a) => a.id).toSet();

    // Se compara contra lo que el sistema tiene programado de verdad, no
    // contra lo que esta ejecución recuerda en memoria: tras reiniciar la app
    // la memoria está vacía, y una alarma de una ruta ya cancelada o
    // reasignada nunca se cancelaba y sonaba igual.
    Iterable<int> guardadas = _scheduledAlarmIds;
    try {
      guardadas = (await Alarm.getAlarms()).map((a) => a.id);
    } catch (e) {
      debugPrint('RouteAlarmService: no se pudieron leer las alarmas: $e');
    }

    final toCancel = idsACancelar(
      guardadas: guardadas,
      deseadas: desired.keys,
      sonando: ringingIds,
      soloAgregar: soloAgregar,
    );
    for (final id in toCancel) {
      try {
        await Alarm.stop(id);
      } catch (e) {
        debugPrint('RouteAlarmService: error cancelando alarma $id: $e');
      }
      _scheduledAlarmIds.remove(id);
    }

    for (final entry in desired.entries) {
      final id = entry.key;
      final plan = entry.value;
      try {
        await Alarm.set(
          alarmSettings: AlarmSettings(
            id: id,
            dateTime: plan.ring,
            assetAudioPath: 'assets/sounds/route_alarm.mp3',
            loopAudio: true,
            vibrate: true,
            warningNotificationOnKill: Platform.isIOS,
            androidFullScreenIntent: true,
            volumeSettings: VolumeSettings.fade(
              volume: 0.8,
              fadeDuration: const Duration(seconds: 5),
              volumeEnforced: true,
            ),
            notificationSettings: NotificationSettings(
              title: 'Ruta a punto de comenzar',
              body:
                  'Debes estar en el punto de inicio de '
                  '"${plan.routeName}" ahora mismo.',
              stopButton: 'Detener',
            ),
          ),
        );
        _scheduledAlarmIds.add(id);
      } catch (e) {
        debugPrint('RouteAlarmService: error programando alarma $id: $e');
      }
    }
  }

  Future<void> _syncNotificationSet(
    Map<int, PlanRuta> desired, {
    bool soloAgregar = false,
  }) async {
    // Igual que con las alarmas: se compara contra lo que el sistema tiene
    // pendiente, no contra la memoria de esta ejecución.
    Iterable<int> pendientes = _scheduledNotificationIds;
    try {
      pendientes = (await _notifications.pendingNotificationRequests()).map(
        (n) => n.id,
      );
    } catch (e) {
      debugPrint('RouteAlarmService: no se pudieron leer los avisos: $e');
    }

    final toCancel = idsACancelar(
      guardadas: pendientes,
      deseadas: desired.keys,
      soloAgregar: soloAgregar,
    );
    for (final id in toCancel) {
      try {
        await _notifications.cancel(id: id);
      } catch (e) {
        debugPrint('RouteAlarmService: error cancelando notif $id: $e');
      }
      _scheduledNotificationIds.remove(id);
    }

    final loc = _location;
    if (loc == null) return;

    for (final entry in desired.entries) {
      final id = entry.key;
      final plan = entry.value;
      final s = plan.start;
      final scheduled = tz.TZDateTime(
        loc,
        s.year,
        s.month,
        s.day,
        s.hour,
        s.minute,
      ).subtract(notificationLead);

      final hora =
          '${s.hour.toString().padLeft(2, '0')}:${s.minute.toString().padLeft(2, '0')}';

      try {
        await _notifications.zonedSchedule(
          id: id,
          title: 'Ruta en 30 minutos',
          body:
              'Tu ruta "${plan.routeName}" es a las $hora. Debes '
              'estar en el punto de inicio en 15 minutos.',
          scheduledDate: scheduled,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _androidChannelId,
              'Recordatorios de ruta',
              channelDescription:
                  'Aviso 30 minutos antes del inicio de cada ruta.',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
        _scheduledNotificationIds.add(id);
      } catch (e) {
        debugPrint('RouteAlarmService: error programando notif $id: $e');
      }
    }
  }

  /// Cancela TODAS las alarmas y notificaciones locales programadas por
  /// este servicio en el dispositivo, sin importar si el proceso de la app
  /// las tiene rastreadas en memoria o no.
  ///
  /// Debe llamarse cuando el chofer cierra sesión en la página web: las
  /// alarmas viven a nivel del sistema operativo, no de la sesión web —
  /// sin esto seguirían sonando en este dispositivo con la cuenta ya
  /// cerrada, incluso si se mata y reabre la app (los sets en memoria se
  /// pierden al reiniciar el proceso, pero lo programado en el SO no). Por
  /// eso usa [Alarm.stopAll] y [FlutterLocalNotificationsPlugin.cancelAll]
  /// en vez de solo recorrer los sets en memoria.
  Future<void> cancelAll() async {
    if (kIsWeb) return;
    try {
      await Alarm.stopAll();
    } catch (e) {
      debugPrint('RouteAlarmService.cancelAll: error deteniendo alarmas: $e');
    }
    try {
      await _notifications.cancelAll();
    } catch (e) {
      debugPrint(
        'RouteAlarmService.cancelAll: error cancelando notificaciones: $e',
      );
    }
    _scheduledAlarmIds.clear();
    _scheduledNotificationIds.clear();
  }

  /// Combina la fecha real de la ruta (`scheduleDate`) con la hora
  /// (`startTime`, que solo trae hora/minuto válidos — su fecha es un
  /// placeholder de RouteModel) para obtener el instante real de inicio.
  static DateTime? _startDateTime(Map<String, dynamic> route) {
    final dia = route['dia'] as String?;
    final hora = route['hora'] as String?;
    if (dia == null || hora == null) return null;
    try {
      final dateParts = dia.split('-').map(int.parse).toList();
      final timeParts = hora.split(':').map(int.parse).toList();
      if (dateParts.length != 3 || timeParts.length < 2) return null;
      return DateTime(
        dateParts[0],
        dateParts[1],
        dateParts[2],
        timeParts[0],
        timeParts[1],
      );
    } catch (_) {
      return null;
    }
  }

  static int _alarmId(String scheduleId) => _fnv1a(scheduleId) & 0x3fffffff;
  static int _notificationId(String scheduleId) =>
      (_fnv1a(scheduleId) & 0x3fffffff) | 0x40000000;

  static int _fnv1a(String input) {
    var hash = 0x811c9dc5;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }
}

/// Lo que hay que programar para una ruta: cuándo suena y cuándo arranca.
class PlanRuta {
  final String routeName;
  final DateTime ring;
  final DateTime start;
  const PlanRuta({
    required this.routeName,
    required this.ring,
    required this.start,
  });
}
