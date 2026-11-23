import 'dart:collection';

import 'package:checkinobra_mobile/core/reloj.dart';
import 'package:checkinobra_mobile/core/sin_reintentos.dart';
import 'package:checkinobra_mobile/core/theme/app_theme.dart';
import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/data/api/cliente_rest.dart';
import 'package:checkinobra_mobile/data/api/dominio_api.dart';
import 'package:checkinobra_mobile/data/modelos/codigo_credencial.dart';
import 'package:checkinobra_mobile/data/modelos/perfil_trabajador.dart';
import 'package:checkinobra_mobile/features/auth/sesion_controller.dart';
import 'package:checkinobra_mobile/features/trabajador/codigo_credencial_controller.dart';
import 'package:checkinobra_mobile/features/trabajador/pantalla_credencial.dart';
import 'package:checkinobra_mobile/features/trabajador/trabajador_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fuentes.dart';

class _SesionTrabajador extends SesionController {
  @override
  Future<SesionUsuario?> build() async => const SesionUsuario(
    token: 't',
    usuarioId: 6,
    nombre: 'Marcelo Sepúlveda',
    rol: 'TRABAJADOR',
    empresaId: 1,
  );
}

const _perfil = PerfilTrabajador(
  id: 1,
  usuarioId: 6,
  nombre: 'Marcelo Sepúlveda',
  rut: '17.930.556-9',
  cuadrillaId: 1,
  cuadrillaNombre: 'Cuadrilla 2',
  obraId: 2,
  obraNombre: 'Los Almendros · Torre B',
  obraEstado: 'ACTIVA',
);

CodigoCredencial _codigo(String texto, {int vigencia = 120}) =>
    CodigoCredencial(
      codigo: texto,
      expiraEn: DateTime.utc(2026, 11, 23, 20, 15),
      vigenciaSegundos: vigencia,
    );

final _sinRed = DioException(
  requestOptions: RequestOptions(
    path: '/api/trabajadores/yo/credencial/codigo',
  ),
  type: DioExceptionType.connectionError,
);

/// Entrega los códigos (o los fallos) que se le pongan en fila, y anota cuántas
/// veces se los pidieron.
class _TrabajadoresFalsos implements TrabajadoresApi {
  _TrabajadoresFalsos(Iterable<Object> respuestas)
    : _respuestas = Queue.of(respuestas);

  final Queue<Object> _respuestas;
  int pedidos = 0;
  int renovaciones = 0;

  /// Lo que responde cuando la fila se acaba.
  Object? siempre;

  void poner(Object respuesta) => _respuestas.add(respuesta);

  @override
  Future<CodigoCredencial> pedirCodigoCredencial() async {
    pedidos++;
    final r = _respuestas.isNotEmpty ? _respuestas.removeFirst() : siempre;
    if (r is CodigoCredencial) return r;
    throw r ?? StateError('la prueba no dejó qué responder');
  }

  @override
  Future<PerfilTrabajador> renovarMiCredencial({String? clave}) async {
    renovaciones++;
    return _perfil;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Un `ClienteRest` que anota la ruta y el cuerpo con que se le escribe.
class _RestQueAnota implements ClienteRest {
  String? ruta;
  Object? cuerpo;

  @override
  Future<T> crear<T>(
    String ruta,
    Object? cuerpo,
    T Function(Map<String, dynamic>) desde, {
    String? clave,
  }) async {
    this.ruta = ruta;
    this.cuerpo = cuerpo;
    return desde({
      'codigo': 'K7M29QXP',
      'expiraEn': '2026-11-23T20:15:00Z',
      'vigenciaSegundos': 120,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _montar(
  WidgetTester tester,
  _TrabajadoresFalsos api, {
  bool activa = true,
}) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_arbol(tester, api, activa: activa));
  // Mientras se pide el código gira un indicador que nunca "termina": se
  // avanza un rato fijo, que alcanza para que responda el falso.
  await tester.pump(const Duration(milliseconds: 100));
}

/// El reloj de la app sigue al reloj de prueba: avanza con cada `pump`.
Widget _arbol(
  WidgetTester tester,
  _TrabajadoresFalsos api, {
  bool activa = true,
}) {
  return ProviderScope(
    retry: sinReintentos,
    overrides: [
      sesionProvider.overrideWith(_SesionTrabajador.new),
      perfilTrabajadorProvider.overrideWith((ref) async => _perfil),
      trabajadoresApiProvider.overrideWithValue(api),
      relojProvider.overrideWithValue(() => tester.binding.clock.now()),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: PantallaCredencial(activa: activa)),
    ),
  );
}

/// El código que lleva el QR que se está mostrando, o `null` si no hay QR.
String? _dato(WidgetTester tester) {
  final qr = find.byType(CodigoQr);
  return qr.evaluate().isEmpty ? null : tester.widget<CodigoQr>(qr).codigo;
}

Future<void> _pasan(WidgetTester tester, int segundos) async {
  for (var i = 0; i < segundos; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

const _sinConexion = 'Sin conexión: no se puede mostrar la credencial';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_CL');
    await cargarInter();
  });

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('checkinobra/pantalla'),
          (call) async => null,
        );
  });

  group('El código', () {
    test('se lee del contrato del servidor', () {
      final c = CodigoCredencial.desdeJson({
        'codigo': 'K7M29QXP',
        'expiraEn': '2026-11-23T20:15:00Z',
        'vigenciaSegundos': 120,
      });

      expect(c.codigo, 'K7M29QXP');
      expect(c.expiraEn, DateTime.utc(2026, 11, 23, 20, 15));
      expect(c.vigenciaSegundos, 120);
    });

    test('se muestra en dos grupos, para tipearlo', () {
      expect(_codigo('K7M29QXP').agrupado, 'K7M2-9QXP');
    });

    test('se normaliza lo que se escribe: sin guiones, espacios ni '
        'minúsculas', () {
      expect(normalizarCodigoCredencial('K7M2-9QXP'), 'K7M29QXP');
      expect(normalizarCodigoCredencial('  k7m2-9qxp  '), 'K7M29QXP');
      expect(normalizarCodigoCredencial('k7m2 9qxp'), 'K7M29QXP');
      expect(normalizarCodigoCredencial('K7M29QXP'), 'K7M29QXP');
    });

    test('el perfil ya no trae la credencial', () {
      final p = PerfilTrabajador.desdeJson({
        'id': 1,
        'usuarioId': 6,
        'nombre': 'Marcelo Sepúlveda',
        // Un servidor viejo podría seguir mandándola: la app no la toma.
        'credencialQr': '7f3a9c2e-1b44-4d7a-9c10-aaaaaaaaaaaa',
      });

      expect(p.aJson().containsKey('credencialQr'), isFalse);
    });

    test('se pide con POST /api/trabajadores/yo/credencial/codigo', () async {
      final rest = _RestQueAnota();

      final c = await TrabajadoresApi(rest).pedirCodigoCredencial();

      expect(rest.ruta, '/api/trabajadores/yo/credencial/codigo');
      expect(c.codigo, 'K7M29QXP');
    });
  });

  group('Credencial del trabajador', () {
    testWidgets('pide un código al abrir y lo muestra, en QR y en texto', (
      tester,
    ) async {
      final api = _TrabajadoresFalsos([_codigo('K7M29QXP')]);
      await _montar(tester, api);

      expect(api.pedidos, 1);
      expect(_dato(tester), 'K7M29QXP');
      expect(find.text('K7M2-9QXP'), findsOneWidget);
      expect(find.text('Marcelo Sepúlveda'), findsOneWidget);
    });

    testWidgets('muestra cuánto falta para que venza', (tester) async {
      final api = _TrabajadoresFalsos([_codigo('K7M29QXP')])
        ..siempre = _codigo('AAAAAAAA');
      await _montar(tester, api);

      expect(find.text('Vence en 2:00'), findsOneWidget);

      await _pasan(tester, 30);
      expect(find.text('Vence en 1:30'), findsOneWidget);
    });

    testWidgets('se renueva solo cada 60 segundos, con un código nuevo', (
      tester,
    ) async {
      final api = _TrabajadoresFalsos([
        _codigo('AAAA1111'),
        _codigo('BBBB2222'),
        _codigo('CCCC3333'),
      ]);
      await _montar(tester, api);
      expect(_dato(tester), 'AAAA1111');

      await _pasan(tester, 59);
      expect(api.pedidos, 1);
      expect(_dato(tester), 'AAAA1111');

      await _pasan(tester, 1);
      expect(api.pedidos, 2);
      expect(_dato(tester), 'BBBB2222');
      // Al renovarse, el contador vuelve a la vigencia completa.
      expect(find.text('Vence en 2:00'), findsOneWidget);

      await _pasan(tester, 60);
      expect(api.pedidos, 3);
      expect(_dato(tester), 'CCCC3333');
    });

    testWidgets('si la renovación falla pero el código sigue vigente, lo '
        'sigue mostrando', (tester) async {
      final api = _TrabajadoresFalsos([_codigo('AAAA1111'), _sinRed]);
      await _montar(tester, api);

      await _pasan(tester, 60);

      expect(api.pedidos, 2);
      // Le quedan 60 s de vida: todavía sirve en bodega.
      expect(_dato(tester), 'AAAA1111');
      expect(find.text(_sinConexion), findsNothing);
    });

    testWidgets('cuando el código vence y no se pudo renovar, no deja un QR '
        'que no sirve', (tester) async {
      final api = _TrabajadoresFalsos([_codigo('AAAA1111')])..siempre = _sinRed;
      await _montar(tester, api);

      await _pasan(tester, 120);

      expect(_dato(tester), isNull);
      expect(find.text(_sinConexion), findsOneWidget);
      expect(find.text('Mostrar en bodega'), findsNothing);
    });

    testWidgets('sin conexión al abrir: mensaje claro, ningún QR', (
      tester,
    ) async {
      final api = _TrabajadoresFalsos([_sinRed]);
      await _montar(tester, api);

      expect(find.text(_sinConexion), findsOneWidget);
      expect(_dato(tester), isNull);
      expect(find.text('Mostrar en bodega'), findsNothing);
    });

    testWidgets('Reintentar pide otro código y, si llega, lo muestra', (
      tester,
    ) async {
      final api = _TrabajadoresFalsos([_sinRed, _codigo('DDDD4444')]);
      await _montar(tester, api);

      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(api.pedidos, 2);
      expect(_dato(tester), 'DDDD4444');
      expect(find.text(_sinConexion), findsNothing);
    });

    testWidgets('vuelve a intentarlo solo cuando no hay código', (
      tester,
    ) async {
      final api = _TrabajadoresFalsos([_sinRed, _codigo('EEEE5555')]);
      await _montar(tester, api);
      expect(_dato(tester), isNull);

      await _pasan(tester, 10);

      expect(api.pedidos, 2);
      expect(_dato(tester), 'EEEE5555');
    });

    testWidgets('un error que no es de red muestra el mensaje del servidor', (
      tester,
    ) async {
      final api = _TrabajadoresFalsos([
        const ApiException(409, 'Tu cuenta no tiene credencial.'),
      ]);
      await _montar(tester, api);

      expect(find.text('Tu cuenta no tiene credencial.'), findsOneWidget);
      expect(find.text(_sinConexion), findsNothing);
      expect(_dato(tester), isNull);
    });

    testWidgets('en otra pestaña no pide nada', (tester) async {
      final api = _TrabajadoresFalsos([_codigo('AAAA1111')]);
      await _montar(tester, api, activa: false);

      await _pasan(tester, 90);

      expect(api.pedidos, 0);
      expect(_dato(tester), isNull);
    });

    testWidgets('al volver a la pestaña pide uno nuevo y no reutiliza el '
        'anterior', (tester) async {
      final api = _TrabajadoresFalsos([
        _codigo('AAAA1111'),
        _codigo('BBBB2222'),
      ]);
      await _montar(tester, api);
      expect(_dato(tester), 'AAAA1111');

      // Se va a otra pestaña…
      await tester.pumpWidget(_arbol(tester, api, activa: false));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_dato(tester), isNull);

      // …y vuelve: es un código recién emitido.
      await tester.pumpWidget(_arbol(tester, api, activa: true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.pedidos, 2);
      expect(_dato(tester), 'BBBB2222');
    });

    testWidgets('si la pestaña está inactiva, deja de renovar', (tester) async {
      final api = _TrabajadoresFalsos([_codigo('AAAA1111')])
        ..siempre = _codigo('ZZZZ9999');
      await _montar(tester, api);
      await tester.pumpWidget(_arbol(tester, api, activa: false));
      await tester.pump(const Duration(milliseconds: 100));
      final antes = api.pedidos;

      await _pasan(tester, 180);

      expect(api.pedidos, antes);
    });

    testWidgets('al reanudar la app con el código ya vencido, no lo muestra '
        'y pide otro', (tester) async {
      final api = _TrabajadoresFalsos([_codigo('AAAA1111')])
        ..siempre = _codigo('FFFF6666');
      await _montar(tester, api);

      // El teléfono estuvo apagado más tiempo que la vigencia: los temporizadores
      // no corrieron, pero el reloj sí.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 5));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(_dato(tester), isNot('AAAA1111'));
      expect(_dato(tester), 'FFFF6666');
    });
  });

  group('Mostrar en bodega', () {
    testWidgets('a pantalla completa va el mismo código, agrupado', (
      tester,
    ) async {
      final api = _TrabajadoresFalsos([_codigo('K7M29QXP')])
        ..siempre = _codigo('K7M29QXP');
      await _montar(tester, api);

      await tester.tap(find.text('Mostrar en bodega'));
      await tester.pumpAndSettle();

      expect(find.byType(PantallaCredencialCompleta), findsOneWidget);
      expect(_dato(tester), 'K7M29QXP');
      expect(find.text('K7M2-9QXP'), findsWidgets);
      expect(find.textContaining('Vence en'), findsWidgets);
    });

    testWidgets('a pantalla completa también se renueva', (tester) async {
      final api = _TrabajadoresFalsos([
        _codigo('AAAA1111'),
        _codigo('BBBB2222'),
      ]);
      await _montar(tester, api);
      await tester.tap(find.text('Mostrar en bodega'));
      await tester.pumpAndSettle();

      await _pasan(tester, 60);

      expect(_dato(tester), 'BBBB2222');
      expect(find.text('BBBB-2222'), findsWidgets);
    });

    testWidgets('si el código caduca estando abierta, avisa en vez de dejar '
        'un QR muerto', (tester) async {
      final api = _TrabajadoresFalsos([_codigo('AAAA1111')])..siempre = _sinRed;
      await _montar(tester, api);
      await tester.tap(find.text('Mostrar en bodega'));
      await tester.pumpAndSettle();

      await _pasan(tester, 120);

      expect(_dato(tester), isNull);
      expect(find.text(_sinConexion), findsOneWidget);
    });
  });

  group('Renovar la credencial', () {
    testWidgets('revoca los vigentes y pide un código nuevo', (tester) async {
      final api = _TrabajadoresFalsos([
        _codigo('AAAA1111'),
        _codigo('BBBB2222'),
      ]);
      await _montar(tester, api);

      await tester.ensureVisible(find.text('Perdí el teléfono: renovar'));
      await tester.tap(find.text('Perdí el teléfono: renovar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Renovar'));
      await tester.pumpAndSettle();

      expect(api.renovaciones, 1);
      expect(api.pedidos, 2);
      expect(_dato(tester), 'BBBB2222');
    });
  });

  group('Mensajes', () {
    test('la falta de red se dice igual en todas las pantallas', () {
      expect(mensajeCredencialSinRed, _sinConexion);
    });
  });
}
