import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxicab_viewer/services/alarm_policy.dart';
import 'package:taxicab_viewer/services/push_owner_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('sin nada guardado devuelve null', () async {
    expect(await PushOwnerStore().read(), isNull);
  });

  test(
    'lo guardado sobrevive a una instancia nueva (como al reiniciar)',
    () async {
      await PushOwnerStore().write(
        const DuenoPush(choferId: 'ana', token: 'tok-1'),
      );

      final leido = await PushOwnerStore().read();
      expect(leido, isNotNull);
      expect(leido!.choferId, 'ana');
      expect(leido.token, 'tok-1');
    },
  );

  test('un registro nuevo reemplaza al anterior', () async {
    final store = PushOwnerStore();
    await store.write(const DuenoPush(choferId: 'ana', token: 'a'));
    await store.write(const DuenoPush(choferId: 'beto', token: 'b'));
    expect((await store.read())!.choferId, 'beto');
  });

  test('clear lo borra', () async {
    final store = PushOwnerStore();
    await store.write(const DuenoPush(choferId: 'ana', token: 'a'));
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('un dato a medias se trata como si no hubiera nada', () async {
    SharedPreferences.setMockInitialValues({'push_dueno_chofer_id': 'ana'});
    expect(await PushOwnerStore().read(), isNull);
  });
}
