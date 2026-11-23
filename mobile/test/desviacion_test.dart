import 'package:checkinobra_mobile/core/formato.dart';
import 'package:checkinobra_mobile/core/sin_reintentos.dart';
import 'package:checkinobra_mobile/core/theme/app_theme.dart';
import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/data/api/cliente_rest.dart';
import 'package:checkinobra_mobile/data/api/dominio_api.dart';
import 'package:checkinobra_mobile/data/modelos/desviacion.dart';
import 'package:checkinobra_mobile/data/modelos/obra.dart';
import 'package:checkinobra_mobile/data/modelos/presupuesto.dart';
import 'package:checkinobra_mobile/features/bodega/bodega_providers.dart';
import 'package:checkinobra_mobile/features/presupuesto/pantalla_desviacion.dart';
import 'package:checkinobra_mobile/features/presupuesto/pantalla_presupuesto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fuentes.dart';

const _obra = Obra(
  id: 3,
  nombre: 'Los Almendros',
  cliente: 'Inmobiliaria Aconcagua',
  ubicacion: 'Ñuñoa',
  estado: 'ACTIVA',
  jefeTerrenoNombre: 'Ana Rojas',
  jefeTerrenoRut: '12.345.678-5',
);

Presupuesto _presupuesto(String estado) => Presupuesto.desdeJson({
  'id': 11,
  'estado': estado,
  'fechaCongelado': null,
  'total': 92482,
  'obraId': 3,
  'obraNombre': 'Los Almendros',
});

/// El ejemplo del contrato: la volcanita se pasó, el montante no.
Map<String, dynamic> _volcanita({
  Object? desviacionPct = 19.1,
  Object? mermaRealPct = 19.0,
  Object? unidad = 'pl',
  bool superaUmbral = true,
  double montoPresupuestado = 60364,
  double montoEjecutado = 71880,
  double desviacionMonto = 11516,
}) => {
  'materialId': 1,
  'sku': 'TAB-VOL-ST-10',
  'nombre': 'Volcanita ST 10 mm',
  'unidad': unidad,
  'cantidadPresupuestada': 10.08,
  'cantidadEjecutada': 12.0,
  'montoPresupuestado': montoPresupuestado,
  'montoEjecutado': montoEjecutado,
  'desviacionMonto': desviacionMonto,
  'desviacionPct': desviacionPct,
  'superaUmbral': superaUmbral,
  'mermaEstimadaPct': 8.0,
  'mermaRealPct': mermaRealPct,
};

Map<String, dynamic> _montante() => {
  'materialId': 2,
  'sku': 'MET-M60',
  'nombre': 'Montante 60×38',
  'unidad': 'un',
  'cantidadPresupuestada': 40.0,
  'cantidadEjecutada': 38.0,
  'montoPresupuestado': 32118.0,
  'montoEjecutado': 30000.0,
  'desviacionMonto': -2118.0,
  'desviacionPct': -6.6,
  'superaUmbral': false,
  'mermaEstimadaPct': 5.0,
  'mermaRealPct': 4.0,
};

Map<String, dynamic> _json({
  bool superaUmbral = true,
  double desviacionPct = 12.5,
  double ejecutado = 104000,
  double desviacionMonto = 11518,
  List<Map<String, dynamic>>? materiales,
}) => {
  'desviacionPct': desviacionPct,
  'mermaRealVsEstimada': 2.1,
  'presupuestado': 92482.0,
  'ejecutado': ejecutado,
  'desviacionMonto': desviacionMonto,
  'umbralPct': 10.0,
  'superaUmbral': superaUmbral,
  'materiales': materiales ?? [_volcanita(), _montante()],
};

Desviacion _desviacion([Map<String, dynamic>? json]) =>
    Desviacion.desdeJson(json ?? _json());

/// Responde la desviación que se le diga, o falla las veces que se pida.
class _PresupuestosFalsos implements PresupuestosApi {
  _PresupuestosFalsos({this.respuesta, this.fallos = 0});

  Desviacion? respuesta;
  int fallos;
  final pedidas = <int>[];

  @override
  Future<Presupuesto?> porObra(int obraId) async => _presupuesto(estado);

  String estado = 'CONGELADO';

  @override
  Future<List<PresupuestoItem>> items(int presupuestoId) async => const [];

  @override
  Future<Desviacion> desviacion(int presupuestoId) async {
    pedidas.add(presupuestoId);
    if (fallos > 0) {
      fallos--;
      throw const ApiException(500, 'No pudimos calcular la desviación.');
    }
    return respuesta!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Un `ClienteRest` que anota la ruta que se le pide.
class _RestQueAnota implements ClienteRest {
  String? ruta;

  @override
  Future<T> uno<T>(
    String ruta,
    T Function(Map<String, dynamic>) desde, {
    Map<String, dynamic>? params,
  }) async {
    this.ruta = ruta;
    return desde(_json());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _montar(
  WidgetTester tester,
  Widget pantalla,
  _PresupuestosFalsos api,
) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: sinReintentos,
      overrides: [
        obraEnCursoProvider.overrideWithValue(_obra),
        presupuestosApiProvider.overrideWithValue(api),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 780),
            textScaler: TextScaler.linear(1.3),
          ),
          child: pantalla,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _verDesviacion(
  WidgetTester tester, {
  Desviacion? respuesta,
  int fallos = 0,
}) async {
  final api = _PresupuestosFalsos(
    respuesta: respuesta ?? _desviacion(),
    fallos: fallos,
  );
  await _montar(
    tester,
    PantallaDesviacion(presupuesto: _presupuesto('CONGELADO')),
    api,
  );
}

/// Lo que anuncia el lector de pantalla para la fila de ese material.
String _etiquetaDe(WidgetTester tester, String nombre) => tester
    .getSemantics(find.bySemanticsLabel(RegExp('^${RegExp.escape(nombre)}\\.')))
    .label;

Finder _en(Finder dentro, String texto) =>
    find.descendant(of: dentro, matching: find.textContaining(texto));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_CL');
    await cargarInter();
  });

  group('Modelo', () {
    test('lee el contrato completo', () {
      final d = _desviacion();

      expect(d.materiales[1].unidad, 'un');
      expect(d.desviacionPct, 12.5);
      expect(d.mermaRealVsEstimada, 2.1);
      expect(d.presupuestado, 92482);
      expect(d.ejecutado, 104000);
      expect(d.desviacionMonto, 11518);
      expect(d.umbralPct, 10);
      expect(d.superaUmbral, isTrue);
      expect(d.materiales, hasLength(2));
      final v = d.materiales.first;
      expect(v.materialId, 1);
      expect(v.sku, 'TAB-VOL-ST-10');
      expect(v.nombre, 'Volcanita ST 10 mm');
      expect(v.unidad, 'pl');
      expect(v.cantidadPresupuestada, 10.08);
      expect(v.cantidadEjecutada, 12);
      expect(v.montoPresupuestado, 60364);
      expect(v.montoEjecutado, 71880);
      expect(v.desviacionMonto, 11516);
      expect(v.desviacionPct, 19.1);
      expect(v.superaUmbral, isTrue);
      expect(v.mermaEstimadaPct, 8);
      expect(v.mermaRealPct, 19);
    });

    test('un material sin presupuesto trae el porcentaje en null', () {
      final m = DesviacionMaterial.desdeJson(_volcanita(desviacionPct: null));

      expect(m.desviacionPct, isNull);
      expect(m.sinPresupuesto, isTrue);
    });

    test('la unidad puede venir en null', () {
      final m = DesviacionMaterial.desdeJson(_volcanita(unidad: null));

      expect(m.unidad, isNull);
    });

    test(
      'solo es "consumido sin presupuestar" si no había monto y se gastó',
      () {
        final sin = DesviacionMaterial.desdeJson(
          _volcanita(
            desviacionPct: null,
            montoPresupuestado: 0,
            montoEjecutado: 100,
          ),
        );
        final nada = DesviacionMaterial.desdeJson(
          _volcanita(
            desviacionPct: null,
            montoPresupuestado: 0,
            montoEjecutado: 0,
          ),
        );

        expect(sin.consumidoSinPresupuestar, isTrue);
        expect(nada.consumidoSinPresupuestar, isFalse);
        expect(
          DesviacionMaterial.desdeJson(_volcanita()).consumidoSinPresupuestar,
          isFalse,
        );
      },
    );

    test('una merma real sin cubicación llega en null', () {
      final m = DesviacionMaterial.desdeJson(_volcanita(mermaRealPct: null));

      expect(m.mermaRealPct, isNull);
    });

    test('los enteros del JSON también valen como decimales', () {
      final d = Desviacion.desdeJson({
        ..._json(),
        'presupuestado': 92482,
        'ejecutado': 104000,
      });

      expect(d.presupuestado, 92482.0);
    });

    test('sin lista de materiales, queda vacía', () {
      final json = _json()..remove('materiales');

      expect(Desviacion.desdeJson(json).materiales, isEmpty);
    });
  });

  group('Formato', () {
    test('el porcentaje lleva signo y coma decimal', () {
      expect(Formato.porcentajeConSigno(12.5), '+12,5 %');
      expect(Formato.porcentajeConSigno(-6.6), '−6,6 %');
      expect(Formato.porcentajeConSigno(0), '0 %');
      expect(Formato.porcentaje(19), '19 %');
    });

    test('los pesos con signo distinguen más y menos', () {
      expect(Formato.pesosConSigno(11518), '+\$11.518');
      expect(Formato.pesosConSigno(-2118), '−\$2.118');
      expect(Formato.pesosConSigno(0), '\$0');
    });
  });

  group('API', () {
    test('pide GET /api/presupuestos/{id}/desviacion', () async {
      final rest = _RestQueAnota();

      final d = await PresupuestosApi(rest).desviacion(11);

      expect(rest.ruta, '/api/presupuestos/11/desviacion');
      expect(d.superaUmbral, isTrue);
    });
  });

  group('Acceso desde el presupuesto', () {
    Future<void> montarPresupuesto(WidgetTester tester, String estado) async {
      final api = _PresupuestosFalsos(respuesta: _desviacion())
        ..estado = estado;
      await _montar(tester, const Scaffold(body: PantallaPresupuesto()), api);
    }

    testWidgets('un borrador no tiene qué comparar', (tester) async {
      await montarPresupuesto(tester, 'BORRADOR');

      expect(find.text('Ver desviación'), findsNothing);
    });

    testWidgets('un presupuesto aprobado la ofrece', (tester) async {
      await montarPresupuesto(tester, 'APROBADO');

      expect(find.text('Ver desviación'), findsOneWidget);
    });

    testWidgets('uno congelado la ofrece y abre la pantalla', (tester) async {
      await montarPresupuesto(tester, 'CONGELADO');

      await tester.tap(find.text('Ver desviación'));
      await tester.pumpAndSettle();

      expect(find.byType(PantallaDesviacion), findsOneWidget);
      expect(find.text('Volcanita ST 10 mm'), findsOneWidget);
    });
  });

  group('Desviación total (D8)', () {
    testWidgets('muestra el monto y el porcentaje, y lo presupuestado y lo '
        'ejecutado', (tester) async {
      await _verDesviacion(tester);

      expect(find.text('+12,5 %'), findsOneWidget);
      expect(find.text('+\$11.518'), findsOneWidget);
      expect(find.text('\$92.482'), findsOneWidget);
      expect(find.text('\$104.000'), findsOneWidget);
    });

    testWidgets('si supera el umbral lo dice con ícono y texto, no solo con '
        'color', (tester) async {
      await _verDesviacion(tester);

      expect(find.text('Supera el umbral de 10 %'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsWidgets);
    });

    testWidgets('dentro del umbral lo dice, también con ícono', (tester) async {
      await _verDesviacion(
        tester,
        respuesta: _desviacion(
          _json(
            superaUmbral: false,
            desviacionPct: 4.2,
            ejecutado: 96367,
            desviacionMonto: 3885,
            materiales: [_montante()],
          ),
        ),
      );

      expect(find.text('Dentro del umbral de 10 %'), findsOneWidget);
      expect(find.text('Supera el umbral de 10 %'), findsNothing);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('el total muestra la merma real contra la estimada', (
      tester,
    ) async {
      await _verDesviacion(tester);

      expect(find.textContaining('+2,1 puntos'), findsOneWidget);
    });
  });

  group('Por material (D8)', () {
    testWidgets('cada material muestra su monto y su porcentaje', (
      tester,
    ) async {
      await _verDesviacion(tester);

      final fila = find.byKey(const ValueKey('material-1'));
      expect(_en(fila, 'Volcanita ST 10 mm'), findsOneWidget);
      expect(_en(fila, 'TAB-VOL-ST-10'), findsOneWidget);
      expect(_en(fila, '+19,1 %'), findsOneWidget);
      expect(_en(fila, '+\$11.516'), findsOneWidget);
      expect(_en(fila, '\$60.364'), findsOneWidget);
      expect(_en(fila, '\$71.880'), findsOneWidget);
      expect(_en(fila, '10,08 pl'), findsOneWidget);
      expect(_en(fila, '12 pl'), findsOneWidget);
    });

    testWidgets('solo el material que supera el umbral se destaca', (
      tester,
    ) async {
      await _verDesviacion(tester);

      expect(
        _en(find.byKey(const ValueKey('material-1')), 'Supera el umbral'),
        findsOneWidget,
      );
      expect(
        _en(find.byKey(const ValueKey('material-2')), 'Supera el umbral'),
        findsNothing,
      );
    });

    testWidgets('gastar menos de lo presupuestado se ve con signo menos', (
      tester,
    ) async {
      await _verDesviacion(tester);

      final fila = find.byKey(const ValueKey('material-2'));
      expect(_en(fila, '−6,6 %'), findsOneWidget);
      expect(_en(fila, '−\$2.118'), findsOneWidget);
    });

    testWidgets('un material consumido sin presupuestar dice "sin '
        'presupuesto"', (tester) async {
      await _verDesviacion(
        tester,
        respuesta: _desviacion(
          _json(
            materiales: [
              _volcanita(
                desviacionPct: null,
                superaUmbral: false,
                montoPresupuestado: 0,
                montoEjecutado: 71880,
                desviacionMonto: 71880,
              ),
            ],
          ),
        ),
      );

      final fila = find.byKey(const ValueKey('material-1'));
      expect(_en(fila, 'sin presupuesto'), findsOneWidget);
      expect(_en(fila, '+\$71.880'), findsOneWidget);
      // El servidor no lo marca (no hay porcentaje contra qué medir), pero es
      // plata gastada sin respaldo: se destaca igual, con ícono y texto.
      expect(_en(fila, 'Consumido sin presupuestar'), findsOneWidget);
      expect(_en(fila, 'Supera el umbral'), findsNothing);
    });

    testWidgets('el catálogo no tiene unidad: sin ella, la cantidad va sola', (
      tester,
    ) async {
      await _verDesviacion(
        tester,
        respuesta: _desviacion(_json(materiales: [_volcanita(unidad: null)])),
      );

      final fila = find.byKey(const ValueKey('material-1'));
      expect(_en(fila, '10,08'), findsOneWidget);
      expect(_en(fila, 'null'), findsNothing);
    });

    testWidgets('mantiene el orden que manda el servidor', (tester) async {
      await _verDesviacion(tester);

      final primero = tester.getTopLeft(
        find.byKey(const ValueKey('material-1')),
      );
      final segundo = tester.getTopLeft(
        find.byKey(const ValueKey('material-2')),
      );
      expect(primero.dy, lessThan(segundo.dy));
    });
  });

  group('Merma (D9)', () {
    testWidgets('muestra la merma estimada y la real de cada material', (
      tester,
    ) async {
      await _verDesviacion(tester);

      final fila = find.byKey(const ValueKey('material-1'));
      expect(_en(fila, 'Merma estimada 8 %'), findsOneWidget);
      expect(_en(fila, 'real 19 %'), findsOneWidget);
    });

    testWidgets('la merma real que se pasó de la estimada lo avisa', (
      tester,
    ) async {
      await _verDesviacion(tester);

      expect(
        _en(find.byKey(const ValueKey('material-1')), 'más que la estimada'),
        findsOneWidget,
      );
      expect(
        _en(find.byKey(const ValueKey('material-2')), 'más que la estimada'),
        findsNothing,
      );
    });

    testWidgets('sin cubicación, la merma real queda como "sin cubicación"', (
      tester,
    ) async {
      await _verDesviacion(
        tester,
        respuesta: _desviacion(
          _json(materiales: [_volcanita(mermaRealPct: null)]),
        ),
      );

      final fila = find.byKey(const ValueKey('material-1'));
      expect(_en(fila, 'Merma estimada 8 %'), findsOneWidget);
      expect(_en(fila, 'real: sin cubicación'), findsOneWidget);
    });
  });

  group('Estados', () {
    testWidgets('mientras carga muestra el avance', (tester) async {
      final api = _PresupuestosFalsos(respuesta: _desviacion());
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: sinReintentos,
          overrides: [
            obraEnCursoProvider.overrideWithValue(_obra),
            presupuestosApiProvider.overrideWithValue(api),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: PantallaDesviacion(presupuesto: _presupuesto('CONGELADO')),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('sin consumo todavía lo explica', (tester) async {
      await _verDesviacion(
        tester,
        respuesta: _desviacion(
          _json(
            superaUmbral: false,
            desviacionPct: -100,
            ejecutado: 0,
            desviacionMonto: -92482,
            materiales: const [],
          ),
        ),
      );

      expect(find.text('Aún no hay consumo en bodega'), findsOneWidget);
      expect(find.byKey(const ValueKey('material-1')), findsNothing);
    });

    testWidgets('un error ofrece Reintentar y, al tocarlo, carga', (
      tester,
    ) async {
      await _verDesviacion(tester, fallos: 1);

      expect(find.text('No pudimos calcular la desviación.'), findsOneWidget);
      expect(find.text('Volcanita ST 10 mm'), findsNothing);

      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(find.text('Volcanita ST 10 mm'), findsOneWidget);
      expect(find.text('No pudimos calcular la desviación.'), findsNothing);
    });
  });

  group('Accesibilidad', () {
    testWidgets('un material que se pasó se anuncia como tal, sin depender del '
        'color', (tester) async {
      final handle = tester.ensureSemantics();
      await _verDesviacion(tester);

      final etiqueta = _etiquetaDe(tester, 'Volcanita ST 10 mm');
      expect(etiqueta, contains('Volcanita ST 10 mm'));
      expect(etiqueta, contains('supera el umbral'));
      expect(etiqueta, contains('+19,1 %'));

      final otra = _etiquetaDe(tester, 'Montante 60×38');
      expect(otra, isNot(contains('supera el umbral')));

      handle.dispose();
    });

    testWidgets('un material sin presupuesto se anuncia como tal', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _verDesviacion(
        tester,
        respuesta: _desviacion(
          _json(materiales: [_volcanita(desviacionPct: null)]),
        ),
      );

      final etiqueta = _etiquetaDe(tester, 'Volcanita ST 10 mm');
      expect(etiqueta, contains('sin presupuesto'));

      handle.dispose();
    });

    testWidgets('lo consumido sin presupuestar se anuncia como alerta', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _verDesviacion(
        tester,
        respuesta: _desviacion(
          _json(
            materiales: [
              _volcanita(
                desviacionPct: null,
                superaUmbral: false,
                montoPresupuestado: 0,
              ),
            ],
          ),
        ),
      );

      expect(
        _etiquetaDe(tester, 'Volcanita ST 10 mm'),
        contains('consumido sin presupuestar'),
      );

      handle.dispose();
    });
  });
}
