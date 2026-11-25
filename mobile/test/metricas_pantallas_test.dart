import 'dart:async';

import 'package:checkinobra_mobile/core/sin_reintentos.dart';
import 'package:checkinobra_mobile/core/theme/app_theme.dart';
import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/data/api/dominio_api.dart';
import 'package:checkinobra_mobile/data/modelos/metricas.dart';
import 'package:checkinobra_mobile/data/modelos/obra.dart';
import 'package:checkinobra_mobile/features/admin/shell_admin.dart';
import 'package:checkinobra_mobile/data/modelos/usuario.dart';
import 'package:checkinobra_mobile/features/bodega/bodega_providers.dart';
import 'package:checkinobra_mobile/features/metricas/pantalla_metricas_admin.dart';
import 'package:checkinobra_mobile/features/metricas/pantalla_metricas_bodega.dart';
import 'package:checkinobra_mobile/features/metricas/pantalla_metricas_jefe.dart';
import 'package:checkinobra_mobile/shared_widgets/graficos/grafico_dona.dart';
import 'package:checkinobra_mobile/shared_widgets/graficos/grafico_vacio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fixtures_metricas.dart';
import 'fuentes.dart';

const _obra = Obra(
  id: 3,
  nombre: 'Los Almendros · Torre B',
  cliente: 'Vista Norte',
  ubicacion: 'Quilicura',
  estado: 'ACTIVA',
  jefeTerrenoNombre: null,
  jefeTerrenoRut: null,
);

/// Responde lo que se le dé y anota con qué periodo le preguntan.
class _MetricasFalsas implements MetricasApi {
  _MetricasFalsas({
    Map<String, dynamic>? jefe,
    Map<String, dynamic>? bodega,
    Map<String, dynamic>? empresa,
  }) : _jefe = jefe ?? jefeJson(),
       _bodega = bodega ?? bodegaJson(),
       _empresa = empresa ?? empresaJson();

  final Map<String, dynamic> _jefe;
  final Map<String, dynamic> _bodega;
  final Map<String, dynamic> _empresa;

  final periodos = <PeriodoMetricas>[];
  final obras = <int>[];
  Object? falla;
  Completer<void>? esperar;

  Future<void> _antes(PeriodoMetricas p, {int? obra}) async {
    periodos.add(p);
    if (obra != null) obras.add(obra);
    if (esperar != null) await esperar!.future;
    if (falla != null) {
      final e = falla!;
      falla = null; // falla una vez; al reintentar responde.
      throw e;
    }
  }

  @override
  Future<MetricasJefe> jefe(int obraId, PeriodoMetricas periodo) async {
    await _antes(periodo, obra: obraId);
    return MetricasJefe.desdeJson(_jefe);
  }

  @override
  Future<MetricasBodega> bodega(int obraId, PeriodoMetricas periodo) async {
    await _antes(periodo, obra: obraId);
    return MetricasBodega.desdeJson(_bodega);
  }

  @override
  Future<MetricasEmpresa> empresa(PeriodoMetricas periodo) async {
    await _antes(periodo);
    return MetricasEmpresa.desdeJson(_empresa);
  }
}

Future<void> _montar(
  WidgetTester tester,
  Widget pantalla,
  _MetricasFalsas api, {
  double escala = 1.3,
}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: sinReintentos,
      overrides: [
        metricasApiProvider.overrideWithValue(api),
        obraEnCursoProvider.overrideWithValue(_obra),
        empresaProvider.overrideWith(
          (ref) async => const Empresa(
            id: 1,
            nombre: 'Constructora Arauco Ltda.',
            rut: '76.412.330-9',
          ),
        ),
        catalogoProvider.overrideWith((ref) async => const []),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 2400),
            textScaler: TextScaler.linear(escala),
          ),
          child: pantalla,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _periodo(WidgetTester tester, String etiqueta) async {
  await tester.tap(find.text(etiqueta));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_CL');
    await cargarInter();
  });

  group('Selector de periodo', () {
    testWidgets('ofrece 7 días, 30 días y Toda la obra, y parte en 30 días', (
      tester,
    ) async {
      final api = _MetricasFalsas();
      await _montar(tester, const PantallaMetricasJefe(), api);

      expect(find.text('7 días'), findsOneWidget);
      expect(find.text('30 días'), findsOneWidget);
      expect(find.text('Toda la obra'), findsOneWidget);
      expect(api.periodos, [PeriodoMetricas.treintaDias]);
    });

    testWidgets('cambiar de periodo vuelve a pedir las métricas con ese '
        'periodo', (tester) async {
      final api = _MetricasFalsas();
      await _montar(tester, const PantallaMetricasJefe(), api);

      await _periodo(tester, '7 días');
      await _periodo(tester, 'Toda la obra');

      expect(api.periodos, [
        PeriodoMetricas.treintaDias,
        PeriodoMetricas.sieteDias,
        PeriodoMetricas.todaLaObra,
      ]);
    });

    testWidgets('el periodo elegido se anuncia como seleccionado', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _montar(tester, const PantallaMetricasJefe(), _MetricasFalsas());

      expect(
        tester.getSemantics(find.text('30 días')),
        isSemantics(
          label: '30 días',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.text('7 días')),
        isSemantics(
          label: '7 días',
          isButton: true,
          isSelected: false,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });

  group('Jefe de terreno', () {
    testWidgets('muestra la obra y sus tres tarjetas', (tester) async {
      await _montar(tester, const PantallaMetricasJefe(), _MetricasFalsas());

      expect(find.text('Métricas'), findsOneWidget);
      expect(find.text('Los Almendros · Torre B'), findsOneWidget);
      expect(find.text('Gasto acumulado por semana'), findsOneWidget);
      expect(find.text('Presupuestado vs ejecutado'), findsOneWidget);
      expect(find.text('Ejecutado por material'), findsOneWidget);
    });

    testWidgets('pide la métrica de la obra en curso', (tester) async {
      final api = _MetricasFalsas();
      await _montar(tester, const PantallaMetricasJefe(), api);

      expect(api.obras, [3]);
    });

    testWidgets(
      'gasto acumulado: cifra, presupuesto y la línea de referencia',
      (tester) async {
        await _montar(tester, const PantallaMetricasJefe(), _MetricasFalsas());

        // La cifra de la tarjeta y el centro de la dona de más abajo.
        expect(find.text('\$52,3 M'), findsNWidgets(2));
        expect(find.text('ejecutado · presupuesto \$48,2 M'), findsOneWidget);
        final lineas = tester
            .widget<LineChart>(find.byType(LineChart))
            .data
            .lineBarsData;
        expect(lineas, hasLength(2));
        expect(
          lineas[1].dashArray,
          isNotNull,
          reason: 'el presupuesto va punteado',
        );
        expect(find.text('Ejecutado acumulado'), findsOneWidget);
        expect(find.text('Presupuesto'), findsWidgets);
      },
    );

    testWidgets('si se pasó del presupuesto, lo dice con texto además del '
        'color', (tester) async {
      await _montar(tester, const PantallaMetricasJefe(), _MetricasFalsas());

      expect(find.text('Supera el presupuesto'), findsOneWidget);
    });

    testWidgets('si no se pasó, no lo dice', (tester) async {
      final json = jefeJson();
      (json['gastoAcumulado'] as Map<String, dynamic>)['ejecutadoTotal'] =
          30000000.0;
      await _montar(
        tester,
        const PantallaMetricasJefe(),
        _MetricasFalsas(jefe: json),
      );

      expect(find.text('Supera el presupuesto'), findsNothing);
      expect(find.text('\$30 M'), findsOneWidget);
    });

    testWidgets('presupuestado vs ejecutado: el material que más se pasó y '
        'una barra doble por material', (tester) async {
      await _montar(tester, const PantallaMetricasJefe(), _MetricasFalsas());

      expect(find.text('+14,4 %'), findsOneWidget);
      expect(
        find.text('Volcanita ST, el material que más se pasó'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('barra-Volcanita ST-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('barra-Volcanita ST-1')),
        findsOneWidget,
      );
      expect(find.text('\$11,8 M'), findsOneWidget);
      expect(find.text('\$13,5 M'), findsOneWidget);
      expect(find.text('Sobre umbral'), findsOneWidget);
    });

    testWidgets('ejecutado por material: la dona con los 4 primeros y «Otros '
        'materiales»', (tester) async {
      await _montar(tester, const PantallaMetricasJefe(), _MetricasFalsas());

      final secciones = tester
          .widget<PieChart>(find.byType(PieChart))
          .data
          .sections;
      expect(secciones, hasLength(5));
      expect(find.text('Otros materiales'), findsOneWidget);
      // 13,5 de 52,3 M.
      expect(find.text('26 %'), findsWidgets);
      expect(find.text('del gasto es Volcanita ST'), findsOneWidget);
      // El centro de la dona: el total en millones y «ejecutado», corto para
      // que no roce el anillo.
      final dona = find.byType(GraficoDona);
      expect(
        find.descendant(of: dona, matching: find.text('\$52,3 M')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dona, matching: find.text('ejecutado')),
        findsOneWidget,
      );
    });

    testWidgets('una obra sin presupuesto: no inventa una referencia ni un '
        'porcentaje', (tester) async {
      final json = jefeJson(
        porMaterial: [
          materialJson(1, 'Volcanita ST', 0, 13500000, null, false),
          materialJson(2, 'Metalcom', 0, 10300000, null, false),
        ],
        otros: {'cantidad': 0, 'ejecutado': 0.0},
      );
      (json['gastoAcumulado'] as Map<String, dynamic>)['presupuestoTotal'] =
          0.0;
      await _montar(
        tester,
        const PantallaMetricasJefe(),
        _MetricasFalsas(jefe: json),
      );

      final lineas = tester
          .widget<LineChart>(find.byType(LineChart))
          .data
          .lineBarsData;
      expect(lineas, hasLength(1), reason: 'sin presupuesto no hay referencia');
      expect(find.textContaining('sin presupuesto'), findsWidgets);
      expect(find.text('Supera el presupuesto'), findsNothing);
      expect(
        find.text('Los materiales consumidos no tienen presupuesto'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin gasto en el periodo: tres estados vacíos claros', (
      tester,
    ) async {
      final api = _MetricasFalsas(
        jefe: {
          'gastoAcumulado': {
            'presupuestoTotal': 1000.0,
            'ejecutadoTotal': 0.0,
            'serie': [],
          },
          'porMaterial': [],
          'otros': {'cantidad': 0, 'ejecutado': 0.0},
          'umbralPct': 10.0,
        },
      );
      await _montar(tester, const PantallaMetricasJefe(), api);

      expect(find.byType(GraficoVacio), findsNWidgets(3));
      expect(find.byType(LineChart), findsNothing);
      expect(find.byType(PieChart), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mientras carga muestra el avance', (tester) async {
      final api = _MetricasFalsas()..esperar = Completer();
      await _montar(tester, const PantallaMetricasJefe(), api);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Gasto acumulado por semana'), findsNothing);

      api.esperar!.complete();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Gasto acumulado por semana'), findsOneWidget);
    });

    testWidgets('un error ofrece Reintentar y, al tocarlo, carga', (
      tester,
    ) async {
      final api = _MetricasFalsas()
        ..falla = const ApiException(500, 'No pudimos calcular las métricas.');
      await _montar(tester, const PantallaMetricasJefe(), api);

      expect(find.text('No pudimos calcular las métricas.'), findsOneWidget);
      expect(find.text('Gasto acumulado por semana'), findsNothing);

      await tester.tap(find.text('Reintentar'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Gasto acumulado por semana'), findsOneWidget);
    });

    testWidgets('los campos que faltan en la respuesta no la rompen', (
      tester,
    ) async {
      await _montar(
        tester,
        const PantallaMetricasJefe(),
        _MetricasFalsas(jefe: const {}),
      );

      expect(find.byType(GraficoVacio), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('cada gráfico lleva su etiqueta para el lector de pantalla', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _montar(tester, const PantallaMetricasJefe(), _MetricasFalsas());

      expect(
        find.bySemanticsLabel(RegExp('^Gráfico de líneas')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('^Gráfico de barras')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('^Gráfico de dona')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('con el texto muy grande no se desborda', (tester) async {
      await _montar(
        tester,
        const PantallaMetricasJefe(),
        _MetricasFalsas(),
        escala: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('Bodega', () {
    testWidgets('muestra sus tres tarjetas', (tester) async {
      await _montar(tester, const PantallaMetricasBodega(), _MetricasFalsas());

      expect(find.text('Movimientos por día'), findsOneWidget);
      expect(find.text('Materiales más despachados'), findsOneWidget);
      expect(find.text('Herramientas de la empresa'), findsOneWidget);
    });

    testWidgets('movimientos: salidas = despacho + consumo y entradas = '
        'recepción', (tester) async {
      await _montar(tester, const PantallaMetricasBodega(), _MetricasFalsas());

      // 10 + 6 + 6 salidas y 3 + 0 + 4 entradas, del mes (30 días).
      expect(find.text('22'), findsOneWidget);
      expect(find.text('salidas en el mes · 7 entradas'), findsOneWidget);
      final lineas = tester
          .widget<LineChart>(find.byType(LineChart))
          .data
          .lineBarsData;
      expect(lineas[0].spots.map((s) => s.y), [10, 6, 6]);
      expect(lineas[1].spots.map((s) => s.y), [3, 0, 4]);
      expect(lineas[1].dashArray, isNotNull);
      expect(find.text('Salidas (despacho y consumo)'), findsOneWidget);
      expect(find.text('Entradas (recepción)'), findsOneWidget);
    });

    testWidgets('el texto de la cifra sigue al periodo', (tester) async {
      await _montar(tester, const PantallaMetricasBodega(), _MetricasFalsas());

      await _periodo(tester, '7 días');
      expect(find.text('salidas en la semana · 7 entradas'), findsOneWidget);

      await _periodo(tester, 'Toda la obra');
      expect(find.text('salidas en toda la obra · 7 entradas'), findsOneWidget);
    });

    testWidgets('los más despachados: ranking con su cantidad', (tester) async {
      await _montar(tester, const PantallaMetricasBodega(), _MetricasFalsas());

      expect(find.text('142'), findsWidgets);
      expect(find.text('de Volcanita ST 10 mm'), findsOneWidget);
      final a = tester
          .getSize(find.byKey(const ValueKey('barra-Volcanita ST 10 mm-0')))
          .width;
      final b = tester
          .getSize(find.byKey(const ValueKey('barra-Montante 90-0')))
          .width;
      expect(a, greaterThan(b));
    });

    testWidgets('herramientas: son de la empresa, y se dice cuántas están '
        'en esta obra', (tester) async {
      await _montar(tester, const PantallaMetricasBodega(), _MetricasFalsas());

      expect(find.text('6'), findsOneWidget);
      expect(
        find.text('prestadas en esta obra · 17 en toda la empresa'),
        findsOneWidget,
      );
      expect(find.text('42'), findsOneWidget);
      for (final t in [
        'Disponibles',
        'Prestadas',
        'En mantención',
        'No devueltas',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
    });

    testWidgets('sin movimientos en el periodo: el vacío es solo de esa '
        'tarjeta', (tester) async {
      final json = bodegaJson()..['movimientos'] = [];
      await _montar(
        tester,
        const PantallaMetricasBodega(),
        _MetricasFalsas(bodega: json),
      );

      expect(find.byType(GraficoVacio), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
      // Las herramientas de la empresa siguen ahí.
      expect(find.byType(PieChart), findsOneWidget);
    });

    testWidgets('sin nada que mostrar: estados vacíos y sin romperse', (
      tester,
    ) async {
      await _montar(
        tester,
        const PantallaMetricasBodega(),
        _MetricasFalsas(bodega: const {}),
      );

      expect(find.byType(GraficoVacio), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('un error ofrece Reintentar', (tester) async {
      final api = _MetricasFalsas()..falla = const ApiException(500, 'Falló.');
      await _montar(tester, const PantallaMetricasBodega(), api);

      expect(find.text('Falló.'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Movimientos por día'), findsOneWidget);
    });

    testWidgets('cada gráfico lleva su etiqueta de lector de pantalla', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _montar(tester, const PantallaMetricasBodega(), _MetricasFalsas());

      expect(
        find.bySemanticsLabel(RegExp('^Gráfico de líneas')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('^Gráfico de barras')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('^Gráfico de dona')), findsOneWidget);
      handle.dispose();
    });
  });

  group('Administrador', () {
    testWidgets('muestra la empresa y sus tres tarjetas', (tester) async {
      await _montar(tester, const PantallaMetricasAdmin(), _MetricasFalsas());

      expect(find.text('Constructora Arauco Ltda.'), findsOneWidget);
      expect(find.text('Alertas por semana'), findsOneWidget);
      expect(find.text('Desviación por obra'), findsOneWidget);
      expect(find.text('Usuarios por rol'), findsOneWidget);
    });

    testWidgets('pide las métricas de la empresa, no de una obra', (
      tester,
    ) async {
      final api = _MetricasFalsas();
      await _montar(tester, const PantallaMetricasAdmin(), api);

      expect(api.periodos, [PeriodoMetricas.treintaDias]);
      expect(api.obras, isEmpty);
    });

    testWidgets('alertas: generadas y resueltas hasta hoy', (tester) async {
      await _montar(tester, const PantallaMetricasAdmin(), _MetricasFalsas());

      expect(find.text('9'), findsOneWidget);
      expect(
        find.text('generadas en S8 · 8 resueltas hasta hoy'),
        findsOneWidget,
      );
      expect(find.text('Generadas'), findsOneWidget);
      expect(find.text('Resueltas hasta hoy'), findsOneWidget);
      final lineas = tester
          .widget<LineChart>(find.byType(LineChart))
          .data
          .lineBarsData;
      expect(lineas[0].spots.map((s) => s.y), [6, 9]);
      expect(lineas[1].spots.map((s) => s.y), [5, 8]);
      expect(lineas[1].dashArray, isNotNull);
    });

    testWidgets('desviación por obra: barras con el umbral y lo que supera '
        'se dice', (tester) async {
      await _montar(tester, const PantallaMetricasAdmin(), _MetricasFalsas());

      expect(find.text('+8,4 %'), findsWidgets);
      expect(
        find.text('Torre B supera el umbral de la empresa'),
        findsOneWidget,
      );
      expect(find.text('umbral 5 %'), findsOneWidget);
      expect(find.byKey(const ValueKey('linea-umbral')), findsOneWidget);
      expect(find.text('-1,5 %'), findsOneWidget);
    });

    testWidgets('una obra sin presupuesto sale como «sin presupuesto», sin '
        'barra', (tester) async {
      await _montar(tester, const PantallaMetricasAdmin(), _MetricasFalsas());

      expect(find.text('sin presupuesto'), findsOneWidget);
      expect(find.byKey(const ValueKey('barra-Sin presupuesto')), findsNothing);
    });

    testWidgets('si ninguna obra supera el umbral, no dice que sí', (
      tester,
    ) async {
      final json = empresaJson()
        ..['desviacionPorObra'] = [
          {'obraId': 1, 'nombre': 'Torre B', 'desviacionPct': 2.0},
          {'obraId': 2, 'nombre': 'Torre C', 'desviacionPct': -1.0},
        ];
      await _montar(
        tester,
        const PantallaMetricasAdmin(),
        _MetricasFalsas(empresa: json),
      );

      expect(find.textContaining('supera el umbral'), findsNothing);
      expect(
        find.text('Torre B es la obra con más desviación'),
        findsOneWidget,
      );
    });

    testWidgets('usuarios por rol: la dona con porcentajes', (tester) async {
      await _montar(tester, const PantallaMetricasAdmin(), _MetricasFalsas());

      expect(find.text('11'), findsOneWidget);
      expect(find.text('son trabajadores de obra'), findsOneWidget);
      // 11 de 23 usuarios.
      expect(find.text('48 %'), findsOneWidget);
      for (final t in [
        'Trabajadores',
        'Bodegueros',
        'Jefes de terreno',
        'Administradores',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('23'), findsOneWidget);
    });

    testWidgets('sin alertas ni obras ni usuarios: tres vacíos claros', (
      tester,
    ) async {
      await _montar(
        tester,
        const PantallaMetricasAdmin(),
        _MetricasFalsas(empresa: const {}),
      );

      expect(find.byType(GraficoVacio), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('un error ofrece Reintentar', (tester) async {
      final api = _MetricasFalsas()..falla = const ApiException(500, 'Falló.');
      await _montar(tester, const PantallaMetricasAdmin(), api);

      expect(find.text('Falló.'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Alertas por semana'), findsOneWidget);
    });

    testWidgets('cada gráfico lleva su etiqueta de lector de pantalla', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _montar(tester, const PantallaMetricasAdmin(), _MetricasFalsas());

      expect(
        find.bySemanticsLabel(RegExp('^Gráfico de líneas')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('^Gráfico de barras')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('^Gráfico de dona')), findsOneWidget);
      handle.dispose();
    });
  });
}
