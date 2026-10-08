import 'package:flutter_test/flutter_test.dart';
import 'package:taxicab_viewer/services/route_alarm_service.dart';

Map<String, dynamic> ruta(
  String id, {
  String estado = 'confirmado',
  String dia = '2026-10-09',
  String? hora = '10:00',
  String nombre = 'Ruta Lego',
}) => {'id': id, 'ruta': nombre, 'estado': estado, 'dia': dia, 'hora': hora};

void main() {
  // Un jueves a las 8:00.
  final ahora = DateTime(2026, 10, 9, 8, 0);

  test(
    'una ruta de hoy más tarde programa aviso 30 min y alarma 15 min antes',
    () {
      final plan = RouteAlarmService.planificar([ruta('r1')], ahora);

      expect(plan.alarmas, hasLength(1));
      expect(plan.notificaciones, hasLength(1));
      expect(plan.alarmas.values.single.ring, DateTime(2026, 10, 9, 9, 45));
      expect(
        plan.notificaciones.values.single.ring,
        DateTime(2026, 10, 9, 9, 30),
      );
      expect(plan.alarmas.values.single.routeName, 'Ruta Lego');
    },
  );

  test(
    'si faltan menos de 15 min la alarma suena ya y no hay aviso previo',
    () {
      final plan = RouteAlarmService.planificar([
        ruta('r1', hora: '08:10'),
      ], ahora);
      expect(plan.alarmas.values.single.ring, ahora);
      expect(plan.notificaciones, isEmpty);
    },
  );

  test('una ruta que ya empezó por hora no programa nada', () {
    final plan = RouteAlarmService.planificar([
      ruta('r1', hora: '07:30'),
    ], ahora);
    expect(plan.alarmas, isEmpty);
    expect(plan.notificaciones, isEmpty);
  });

  test('no programa nada para rutas canceladas ni ya iniciadas', () {
    final estados = [
      'cancelado',
      'cancelado_sin_cobro',
      'cancelado_con_cobro',
      'rechazada',
      'punto_inicio',
      'en_proceso',
      'completado',
      'finalizado',
    ];
    for (final e in estados) {
      final plan = RouteAlarmService.planificar([ruta('r1', estado: e)], ahora);
      expect(plan.alarmas, isEmpty, reason: e);
    }
  });

  test('ignora rutas sin id, sin hora o con datos mal formados', () {
    final plan = RouteAlarmService.planificar([
      ruta(''),
      ruta('r2', hora: null),
      ruta('r3', hora: 'mañana'),
      ruta('r4', dia: 'hoy'),
    ], ahora);
    expect(plan.alarmas, isEmpty);
  });

  test('una lista vacía no programa nada', () {
    final plan = RouteAlarmService.planificar(const [], ahora);
    expect(plan.alarmas, isEmpty);
    expect(plan.notificaciones, isEmpty);
  });

  test(
    'el mismo id da siempre los mismos números y no se mezcla con el aviso',
    () {
      final a = RouteAlarmService.planificar([ruta('r1')], ahora);
      final b = RouteAlarmService.planificar([ruta('r1')], ahora);
      expect(a.alarmas.keys, b.alarmas.keys);
      expect(a.alarmas.keys.single, isNot(a.notificaciones.keys.single));

      final c = RouteAlarmService.planificar([ruta('r1'), ruta('r2')], ahora);
      expect(c.alarmas, hasLength(2));
    },
  );
}
