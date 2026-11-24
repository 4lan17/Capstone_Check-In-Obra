import 'package:checkinobra_mobile/core/formato.dart';
import 'package:checkinobra_mobile/data/api/cliente_rest.dart';
import 'package:checkinobra_mobile/data/api/dominio_api.dart';
import 'package:checkinobra_mobile/data/modelos/metricas.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fixtures_metricas.dart';

class _RestQueAnota implements ClienteRest {
  _RestQueAnota(this.respuesta);

  final Map<String, dynamic> respuesta;
  String? ruta;
  Map<String, dynamic>? params;

  @override
  Future<T> uno<T>(
    String ruta,
    T Function(Map<String, dynamic>) desde, {
    Map<String, dynamic>? params,
  }) async {
    this.ruta = ruta;
    this.params = params;
    return desde(respuesta);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => initializeDateFormatting('es_CL'));

  group('Periodo', () {
    test('cada periodo tiene su código para la API y su etiqueta', () {
      expect(PeriodoMetricas.sieteDias.codigo, '7d');
      expect(PeriodoMetricas.treintaDias.codigo, '30d');
      expect(PeriodoMetricas.todaLaObra.codigo, 'obra');
      expect(PeriodoMetricas.sieteDias.etiqueta, '7 días');
      expect(PeriodoMetricas.treintaDias.etiqueta, '30 días');
      expect(PeriodoMetricas.todaLaObra.etiqueta, 'Toda la obra');
    });
  });

  group('Jefe de terreno', () {
    test('lee el gasto acumulado con su serie', () {
      final m = MetricasJefe.desdeJson(jefeJson());

      expect(m.gastoAcumulado.presupuestoTotal, 48200000);
      expect(m.gastoAcumulado.ejecutadoTotal, 52300000);
      expect(m.gastoAcumulado.serie.map((p) => p.etiqueta), ['S1', 'S2', 'S3']);
      expect(m.gastoAcumulado.serie.last.ejecutadoAcumulado, 52300000);
      expect(m.gastoAcumulado.serie.first.desde, DateTime(2026, 10, 5));
      expect(m.umbralPct, 10);
    });

    test('supera el presupuesto cuando lo ejecutado lo pasa', () {
      expect(
        MetricasJefe.desdeJson(jefeJson()).gastoAcumulado.superaPresupuesto,
        isTrue,
      );
    });

    test('no lo supera si hay menos gasto o no hay presupuesto', () {
      final dentro = GastoAcumulado.desdeJson({
        'presupuestoTotal': 100.0,
        'ejecutadoTotal': 40.0,
        'serie': const [],
      });
      final sin = GastoAcumulado.desdeJson({
        'presupuestoTotal': 0.0,
        'ejecutadoTotal': 40.0,
        'serie': const [],
      });

      expect(dentro.superaPresupuesto, isFalse);
      // Sin presupuesto no hay contra qué pasarse.
      expect(sin.superaPresupuesto, isFalse);
    });

    test('lee los materiales, con el porcentaje que puede ser nulo', () {
      final m = MetricasJefe.desdeJson(jefeJson());

      expect(m.porMaterial, hasLength(5));
      expect(m.porMaterial.first.nombre, 'Volcanita ST');
      expect(m.porMaterial.first.desviacionPct, 14.4);
      expect(m.porMaterial.first.superaUmbral, isTrue);
      expect(m.porMaterial.last.desviacionPct, isNull);
    });

    test('el material que más se pasó es el de mayor desviación', () {
      final m = MetricasJefe.desdeJson(jefeJson());

      expect(m.masPasado!.nombre, 'Volcanita ST');
    });

    test('si ninguno tiene porcentaje, no hay "más pasado"', () {
      final m = MetricasJefe.desdeJson(
        jefeJson(porMaterial: [materialJson(1, 'Clavos', 0, 500, null, false)]),
      );

      expect(m.masPasado, isNull);
    });

    test('la dona: los 4 primeros y «Otros» (el 5.º más el resto)', () {
      final partes = MetricasJefe.desdeJson(jefeJson()).partesDeDona;

      expect(partes.map((p) => p.etiqueta), [
        'Volcanita ST',
        'Metalcom',
        'Pino bruto',
        'Aislante',
        'Otros materiales',
      ]);
      expect(partes.length, lessThanOrEqualTo(5));
      // Otros = 5.º (1,1 M) + «otros» (15,1 M).
      expect(partes.last.valor, 1100000 + 15100000);
    });

    test('con 4 o menos materiales y sin resto, no hay «Otros»', () {
      final m = MetricasJefe.desdeJson(
        jefeJson(
          porMaterial: [
            materialJson(1, 'A', 10, 60, null, false),
            materialJson(2, 'B', 10, 40, null, false),
          ],
          otros: {'cantidad': 0, 'ejecutado': 0.0},
        ),
      );

      expect(m.partesDeDona.map((p) => p.etiqueta), ['A', 'B']);
    });

    test('el porcentaje de cada parte es sobre el total ejecutado', () {
      final m = MetricasJefe.desdeJson(
        jefeJson(
          porMaterial: [
            materialJson(1, 'A', 10, 25, null, false),
            materialJson(2, 'B', 10, 75, null, false),
          ],
          otros: {'cantidad': 0, 'ejecutado': 0.0},
        ),
      );

      expect(m.totalPartes, 100);
      // Van de mayor a menor: B (75) primero, A (25) después.
      expect(m.partesDeDona.first.etiqueta, 'B');
      expect(m.partesDeDona.first.proporcion, 0.75);
      expect(m.partesDeDona.last.proporcion, 0.25);
    });

    test('lo que falta o viene vacío no rompe nada', () {
      final m = MetricasJefe.desdeJson(const {});

      expect(m.gastoAcumulado.serie, isEmpty);
      expect(m.porMaterial, isEmpty);
      expect(m.partesDeDona, isEmpty);
      expect(m.masPasado, isNull);
      expect(m.umbralPct, isNull);
      expect(m.estaVacio, isTrue);
    });

    test('una obra sin gasto está vacía aunque haya presupuesto', () {
      final m = MetricasJefe.desdeJson(const {
        'gastoAcumulado': {
          'presupuestoTotal': 1000.0,
          'ejecutadoTotal': 0.0,
          'serie': [],
        },
        'porMaterial': [],
        'otros': {'cantidad': 0, 'ejecutado': 0.0},
      });

      expect(m.estaVacio, isTrue);
    });

    test('no hay un campo de partidas: se quitó del contrato', () {
      final m = MetricasJefe.desdeJson({
        ...jefeJson(),
        'porPartida': {'items': []},
      });

      expect(m.porMaterial, isNotEmpty);
    });
  });

  group('Bodega', () {
    test('lee los movimientos por día, sin devoluciones', () {
      final m = MetricasBodega.desdeJson(bodegaJson());

      expect(m.granularidad, 'DIA');
      expect(m.movimientos, hasLength(3));
      expect(m.movimientos.first.fecha, DateTime(2026, 11, 16));
      expect(m.movimientos.first.recepcion, 3);
    });

    test('salidas = despacho + consumo; entradas = recepción', () {
      final m = MetricasBodega.desdeJson(bodegaJson());

      expect(m.movimientos.first.salidas, 10);
      expect(m.movimientos.first.entradas, 3);
      expect(m.totalSalidas, 10 + 6 + 6);
      expect(m.totalEntradas, 3 + 0 + 4);
    });

    test('lee los más despachados', () {
      final m = MetricasBodega.desdeJson(bodegaJson());

      expect(m.masDespachados.first.nombre, 'Volcanita ST 10 mm');
      expect(m.masDespachados.first.cantidad, 142);
      expect(m.masDespachados.first.materialId, 1);
    });

    test('las herramientas son de la empresa, y se sabe cuántas están en '
        'esta obra', () {
      final m = MetricasBodega.desdeJson(bodegaJson());

      expect(m.totalHerramientas, 42);
      expect(m.herramientasPorEstado['PRESTADA'], 17);
      expect(m.prestadasEnEstaObra, 6);
    });

    test('lo que falta o viene vacío no rompe nada', () {
      final m = MetricasBodega.desdeJson(const {});

      expect(m.movimientos, isEmpty);
      expect(m.masDespachados, isEmpty);
      expect(m.herramientasPorEstado, isEmpty);
      expect(m.totalHerramientas, 0);
      expect(m.prestadasEnEstaObra, 0);
      expect(m.totalSalidas, 0);
      expect(m.sinMovimientos, isTrue);
    });

    test('sin movimientos aunque haya herramientas: lo de movimientos está '
        'vacío', () {
      final m = MetricasBodega.desdeJson({...bodegaJson(), 'movimientos': []});

      expect(m.sinMovimientos, isTrue);
      expect(m.totalHerramientas, 42);
    });
  });

  group('Administrador', () {
    test('lee las alertas por semana: generadas y resueltas hasta hoy', () {
      final m = MetricasEmpresa.desdeJson(empresaJson());

      expect(m.alertasPorSemana, hasLength(2));
      expect(m.alertasPorSemana.last.etiqueta, 'S8');
      expect(m.alertasPorSemana.last.generadas, 9);
      expect(m.alertasPorSemana.last.resueltas, 8);
    });

    test('lee la desviación por obra, con el porcentaje que puede ser '
        'nulo', () {
      final m = MetricasEmpresa.desdeJson(empresaJson());

      expect(m.desviacionPorObra, hasLength(4));
      expect(m.desviacionPorObra.first.nombre, 'Torre B');
      expect(m.desviacionPorObra.first.desviacionPct, 8.4);
      expect(m.desviacionPorObra.last.desviacionPct, isNull);
      expect(m.umbralPct, 5);
    });

    test('la obra más desviada es la de mayor porcentaje', () {
      final m = MetricasEmpresa.desdeJson(empresaJson());

      expect(m.masDesviada!.nombre, 'Torre B');
      expect(m.masDesviada!.superaUmbral(m.umbralPct), isTrue);
    });

    test('una obra sin presupuesto no supera ningún umbral', () {
      final m = MetricasEmpresa.desdeJson(empresaJson());

      expect(m.desviacionPorObra.last.superaUmbral(m.umbralPct), isFalse);
      expect(m.desviacionPorObra.last.sinPresupuesto, isTrue);
    });

    test('lee los usuarios por rol y las obras por estado', () {
      final m = MetricasEmpresa.desdeJson(empresaJson());

      expect(m.usuariosPorRol['TRABAJADOR'], 11);
      expect(m.totalUsuarios, 23);
      expect(m.obrasPorEstado['ACTIVA'], 3);
    });

    test('lo que falta o viene vacío no rompe nada', () {
      final m = MetricasEmpresa.desdeJson(const {});

      expect(m.alertasPorSemana, isEmpty);
      expect(m.desviacionPorObra, isEmpty);
      expect(m.masDesviada, isNull);
      expect(m.usuariosPorRol, isEmpty);
      expect(m.totalUsuarios, 0);
      expect(m.sinAlertas, isTrue);
    });
  });

  group('API', () {
    test('jefe: GET /api/obras/{id}/metricas/jefe?periodo=', () async {
      final rest = _RestQueAnota(jefeJson());

      final m = await MetricasApi(rest).jefe(3, PeriodoMetricas.treintaDias);

      expect(rest.ruta, '/api/obras/3/metricas/jefe');
      expect(rest.params, {'periodo': '30d'});
      expect(m.porMaterial, isNotEmpty);
    });

    test('bodega: GET /api/obras/{id}/metricas/bodega?periodo=', () async {
      final rest = _RestQueAnota(bodegaJson());

      await MetricasApi(rest).bodega(3, PeriodoMetricas.sieteDias);

      expect(rest.ruta, '/api/obras/3/metricas/bodega');
      expect(rest.params, {'periodo': '7d'});
    });

    test('empresa: GET /api/metricas/empresa?periodo=', () async {
      final rest = _RestQueAnota(empresaJson());

      await MetricasApi(rest).empresa(PeriodoMetricas.todaLaObra);

      expect(rest.ruta, '/api/metricas/empresa');
      expect(rest.params, {'periodo': 'obra'});
    });
  });

  group('Formato de las cifras', () {
    test('los millones llevan una coma y la M', () {
      expect(Formato.millones(52300000), '\$52,3 M');
      expect(Formato.millones(48200000), '\$48,2 M');
      expect(Formato.millones(1000000), '\$1 M');
    });

    test('bajo el millón se muestran los pesos enteros', () {
      expect(Formato.millones(850000), '\$850.000');
      expect(Formato.millones(0), '\$0');
    });

    test('los millones a secas (para el centro de la dona)', () {
      expect(Formato.soloMillones(52300000), '52,3');
    });
  });
}
