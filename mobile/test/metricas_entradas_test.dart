import 'package:checkinobra_mobile/core/sin_reintentos.dart';
import 'package:checkinobra_mobile/core/theme/app_theme.dart';
import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/data/api/dominio_api.dart';
import 'package:checkinobra_mobile/data/modelos/metricas.dart';
import 'package:checkinobra_mobile/data/modelos/obra.dart';
import 'package:checkinobra_mobile/data/modelos/partida.dart';
import 'package:checkinobra_mobile/data/modelos/usuario.dart';
import 'package:checkinobra_mobile/features/admin/pantalla_usuarios.dart';
import 'package:checkinobra_mobile/features/admin/shell_admin.dart';
import 'package:checkinobra_mobile/features/auth/sesion_controller.dart';
import 'package:checkinobra_mobile/features/bodega/bodega_providers.dart';
import 'package:checkinobra_mobile/features/bodega/pantalla_inicio_bodega.dart';
import 'package:checkinobra_mobile/features/cubicacion/pantalla_partidas.dart';
import 'package:checkinobra_mobile/features/obra/obra_activa.dart';
import 'package:checkinobra_mobile/features/metricas/pantalla_metricas_admin.dart';
import 'package:checkinobra_mobile/features/metricas/pantalla_metricas_bodega.dart';
import 'package:checkinobra_mobile/features/metricas/pantalla_metricas_jefe.dart';
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

class _Metricas implements MetricasApi {
  @override
  Future<MetricasJefe> jefe(int obraId, PeriodoMetricas periodo) async =>
      MetricasJefe.desdeJson(jefeJson());

  @override
  Future<MetricasBodega> bodega(int obraId, PeriodoMetricas periodo) async =>
      MetricasBodega.desdeJson(bodegaJson());

  @override
  Future<MetricasEmpresa> empresa(PeriodoMetricas periodo) async =>
      MetricasEmpresa.desdeJson(empresaJson());
}

class _Partidas implements PartidasApi {
  @override
  Future<List<Partida>> porObra(int obraId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SesionAdmin extends SesionController {
  @override
  Future<SesionUsuario?> build() async => const SesionUsuario(
    token: 't',
    usuarioId: 1,
    nombre: 'Carla Muñoz',
    rol: 'ADMIN',
    empresaId: 1,
  );
}

Future<void> _montar(WidgetTester tester, Widget pantalla) async {
  tester.view.physicalSize = const Size(390, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: sinReintentos,
      overrides: [
        sesionProvider.overrideWith(_SesionAdmin.new),
        metricasApiProvider.overrideWithValue(_Metricas()),
        partidasApiProvider.overrideWithValue(_Partidas()),
        obraEnCursoProvider.overrideWithValue(_obra),
        empresaProvider.overrideWith(
          (ref) async => const Empresa(
            id: 1,
            nombre: 'Constructora Arauco Ltda.',
            rut: '76.412.330-9',
          ),
        ),
        catalogoProvider.overrideWith((ref) async => const []),
        todasLasObrasProvider.overrideWith((ref) async => const []),
        usuariosProvider.overrideWith((ref) async => const []),
        movimientosProvider.overrideWith((ref) async => const []),
        prestamosProvider.overrideWith((ref) async => const []),
        alertasProvider.overrideWith((ref) async => const []),
        solicitudesMaterialProvider.overrideWith((ref) async => const []),
        solicitudesHerramientaProvider.overrideWith((ref) async => const []),
        pedidosEspecialesObraProvider.overrideWith((ref) async => const []),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 1800),
            textScaler: TextScaler.linear(1.3),
          ),
          child: pantalla,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_CL');
    await cargarInter();
  });

  testWidgets('el jefe de terreno entra a las métricas de la obra desde sus '
      'partidas', (tester) async {
    await _montar(tester, const Scaffold(body: PantallaPartidas()));

    expect(find.text('Métricas de la obra'), findsOneWidget);
    expect(find.text('Gasto, presupuesto y materiales'), findsOneWidget);

    await tester.tap(find.text('Métricas de la obra'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(PantallaMetricasJefe), findsOneWidget);
    expect(find.text('Gasto acumulado por semana'), findsOneWidget);
  });

  testWidgets('el bodeguero entra a las métricas desde su inicio', (
    tester,
  ) async {
    await _montar(tester, Scaffold(body: PantallaInicioBodega(alIrA: (_) {})));

    final fila = find.text('Métricas de la bodega');
    await tester.ensureVisible(fila);
    expect(find.text('Movimientos, despachos y herramientas'), findsOneWidget);

    await tester.tap(fila);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(PantallaMetricasBodega), findsOneWidget);
    expect(find.text('Movimientos por día'), findsOneWidget);
  });

  testWidgets('el administrador entra a las métricas desde su empresa', (
    tester,
  ) async {
    await _montar(tester, const ShellAdmin());
    await tester.tap(find.text('Empresa'));
    await tester.pump(const Duration(milliseconds: 300));

    final fila = find.text('Métricas de la empresa');
    await tester.ensureVisible(fila);
    expect(find.text('Alertas, desviación y usuarios'), findsOneWidget);

    await tester.tap(fila);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));

    // Las pestañas del admin viven todas montadas, cada una con su botón
    // flotante: si comparten el `heroTag` por defecto, cualquier navegación
    // desde el shell dispara el assert «multiple heroes» (en debug).
    expect(tester.takeException(), isNull);

    expect(find.byType(PantallaMetricasAdmin), findsOneWidget);
    expect(find.text('Alertas por semana'), findsOneWidget);
  });
}
