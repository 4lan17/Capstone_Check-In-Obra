import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/data/api/dominio_api.dart';
import 'package:checkinobra_mobile/data/modelos/trabajador.dart';
import 'package:checkinobra_mobile/features/bodega/resolver_credencial.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _marcelo = Trabajador(
  id: 5,
  rut: '17.930.556-9',
  nombre: 'Marcelo Sepúlveda',
  cuadrillaId: 1,
);

/// Responde como `GET /api/trabajadores/por-credencial/{codigo}`: el código
/// vigente, uno caducado (409) o uno desconocido (404).
class _TrabajadoresFalsos implements TrabajadoresApi {
  _TrabajadoresFalsos({this.falla});

  final Object? falla;
  final pedidos = <String>[];

  @override
  Future<Trabajador> porCredencial(String credencialQr) async {
    pedidos.add(credencialQr);
    if (falla != null) throw falla!;
    return _marcelo;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Leer la credencial en bodega', () {
    test('un código vigente devuelve al trabajador', () async {
      final api = _TrabajadoresFalsos();

      final r = await buscarTrabajadorPorCredencial(api, 'K7M29QXP');

      expect(r.trabajador, _marcelo);
      expect(r.error, isNull);
      expect(api.pedidos, ['K7M29QXP']);
    });

    test('acepta el código con guion, espacios y en minúsculas', () async {
      for (final escrito in ['K7M2-9QXP', 'k7m2-9qxp', ' k7m2 9qxp ']) {
        final api = _TrabajadoresFalsos();

        await buscarTrabajadorPorCredencial(api, escrito);

        expect(api.pedidos, ['K7M29QXP'], reason: escrito);
      }
    });

    test('una credencial caducada (409) dice qué hacer', () async {
      final api = _TrabajadoresFalsos(
        falla: const ApiException(
          409,
          'La credencial caducó.',
          codigo: 'CREDENCIAL_CADUCADA',
        ),
      );

      final r = await buscarTrabajadorPorCredencial(api, 'K7M29QXP');

      expect(r.trabajador, isNull);
      expect(
        r.error,
        'La credencial caducó: pídele al trabajador que la muestre de nuevo.',
      );
    });

    test(
      'un código desconocido (404) no promete que "puede estar vencido"',
      () async {
        final api = _TrabajadoresFalsos(
          falla: const ApiException(404, 'Código no reconocido'),
        );

        final r = await buscarTrabajadorPorCredencial(api, 'K7M29QXP');

        expect(r.error, contains('no corresponde a ningún trabajador'));
        // Un caducado tiene su propio mensaje: acá ya no se adivina.
        expect(r.error, isNot(contains('vencida')));
        expect(r.error, isNot(contains('caducó')));
      },
    );

    test('otro error del servidor se muestra tal cual', () async {
      final api = _TrabajadoresFalsos(
        falla: const ApiException(500, 'No pudimos buscar.'),
      );

      final r = await buscarTrabajadorPorCredencial(api, 'K7M29QXP');

      expect(r.error, 'No pudimos buscar.');
    });

    test('sin red, el mensaje de red', () async {
      final api = _TrabajadoresFalsos(
        falla: DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionError,
        ),
      );

      final r = await buscarTrabajadorPorCredencial(api, 'K7M29QXP');

      expect(r.error, contains('No hay conexión'));
    });

    test('un código vacío no llama al servidor', () async {
      final api = _TrabajadoresFalsos();

      final r = await buscarTrabajadorPorCredencial(api, ' - ');

      expect(api.pedidos, isEmpty);
      expect(r.error, isNotNull);
    });
  });
}
