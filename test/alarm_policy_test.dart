import 'package:flutter_test/flutter_test.dart';
import 'package:taxicab_viewer/services/alarm_policy.dart';

void main() {
  group('idsACancelar', () {
    test('cancela una alarma guardada cuya ruta ya no está', () {
      expect(idsACancelar(guardadas: [1, 2, 3], deseadas: [1, 3]), {2});
    });

    test('tras reiniciar la app (memoria vacía) igual cancela las viejas', () {
      // Antes se comparaba contra una lista en memoria que quedaba vacía al
      // reiniciar, y la alarma de una ruta cancelada nunca se quitaba. Ahora
      // se compara contra lo que el sistema tiene guardado.
      expect(idsACancelar(guardadas: [10, 20], deseadas: const []), {10, 20});
    });

    test('no cancela la que está sonando', () {
      expect(
        idsACancelar(guardadas: [1, 2], deseadas: const [], sonando: [2]),
        {1},
      );
    });

    test('con soloAgregar no cancela nada', () {
      // El aviso push trae UNA ruta; no es la lista completa de hoy.
      expect(
        idsACancelar(guardadas: [1, 2, 3], deseadas: [3], soloAgregar: true),
        isEmpty,
      );
    });

    test('sin alarmas guardadas no hay nada que cancelar', () {
      expect(idsACancelar(guardadas: const [], deseadas: [1]), isEmpty);
    });

    test('un id repetido se cancela una sola vez', () {
      expect(idsACancelar(guardadas: [4, 4], deseadas: const []), {4});
    });
  });

  group('puedeAbrirAjustes', () {
    test('la primera vez y sin alarma sonando, sí', () {
      expect(
        puedeAbrirAjustes(
          yaSePidioEnEstaEjecucion: false,
          hayAlarmaSonando: false,
        ),
        isTrue,
      );
    });

    test('nunca mientras suena una alarma: taparía el botón Detener', () {
      expect(
        puedeAbrirAjustes(
          yaSePidioEnEstaEjecucion: false,
          hayAlarmaSonando: true,
        ),
        isFalse,
      );
    });

    test('no se repite en la misma ejecución', () {
      expect(
        puedeAbrirAjustes(
          yaSePidioEnEstaEjecucion: true,
          hayAlarmaSonando: false,
        ),
        isFalse,
      );
    });
  });

  group('decidirRegistro', () {
    const ana = DuenoPush(choferId: 'ana', token: 't1');

    test('primera vez en el teléfono: solo registrar', () {
      expect(
        decidirRegistro(guardado: null, choferNuevo: 'ana'),
        AccionRegistroPush.registrar,
      );
    });

    test('la misma cuenta de siempre: solo registrar', () {
      expect(
        decidirRegistro(guardado: ana, choferNuevo: 'ana'),
        AccionRegistroPush.registrar,
      );
    });

    test('entra otra cuenta: se da de baja la anterior', () {
      expect(
        decidirRegistro(guardado: ana, choferNuevo: 'beto'),
        AccionRegistroPush.darDeBajaAnteriorYRegistrar,
      );
    });
  });

  group('avisoEsParaEsteChofer', () {
    test('un aviso de otra persona se ignora', () {
      expect(
        avisoEsParaEsteChofer(choferDelAviso: 'ana', choferRegistrado: 'beto'),
        isFalse,
      );
    });

    test('un aviso de la misma persona se acepta', () {
      expect(
        avisoEsParaEsteChofer(choferDelAviso: 'ana', choferRegistrado: 'ana'),
        isTrue,
      );
    });

    test('si el aviso no dice de quién es (servidor actual), se acepta', () {
      expect(
        avisoEsParaEsteChofer(choferDelAviso: null, choferRegistrado: 'beto'),
        isTrue,
      );
      expect(
        avisoEsParaEsteChofer(choferDelAviso: '', choferRegistrado: 'beto'),
        isTrue,
      );
    });

    test('si la app no sabe quién usa el teléfono, se acepta', () {
      expect(
        avisoEsParaEsteChofer(choferDelAviso: 'ana', choferRegistrado: null),
        isTrue,
      );
    });
  });
}
