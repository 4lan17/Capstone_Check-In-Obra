import 'package:checkinobra_mobile/core/sin_reintentos.dart';
import 'package:checkinobra_mobile/core/theme/app_theme.dart';
import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/data/api/dominio_api.dart';
import 'package:checkinobra_mobile/data/modelos/material.dart';
import 'package:checkinobra_mobile/data/modelos/solicitud.dart';
import 'package:checkinobra_mobile/features/auth/sesion_controller.dart';
import 'package:checkinobra_mobile/features/bodega/bodega_providers.dart';
import 'package:checkinobra_mobile/features/bodega/pantalla_solicitudes.dart';
import 'package:checkinobra_mobile/features/trabajador/filas_trabajador.dart';
import 'package:checkinobra_mobile/features/trabajador/trabajador_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fuentes.dart';

const _motivo = 'No hay stock suficiente hasta el lunes';
const _yaResuelta = ApiException(
  409,
  'La solicitud ya fue resuelta',
  codigo: 'YA_RESUELTA',
);

Map<String, dynamic> _jsonMaterial({
  int id = 1,
  String estado = 'PENDIENTE',
  String? motivo,
  String? resueltoPor,
}) => {
  'id': id,
  'cantidad': 36.0,
  'estado': estado,
  'fechaSolicitud': '2026-09-02T08:14:00',
  'motivoRechazo': motivo,
  'trabajadorId': 5,
  'trabajadorNombre': 'Marcelo Sepúlveda',
  'trabajadorRut': '17.930.556-9',
  'materialId': 2,
  'materialSku': 'VOL-ST-10',
  'materialNombre': 'Volcanita ST 10 mm',
  'obraId': 3,
  'resueltoPorId': resueltoPor == null ? null : 9,
  'resueltoPorNombre': resueltoPor,
};

Map<String, dynamic> _jsonHerramienta({
  int id = 1,
  String estado = 'PENDIENTE',
  String? motivo,
  String? resueltoPor,
}) => {
  'id': id,
  'cantidad': 1,
  'estado': estado,
  'fechaSolicitud': '2026-09-02T09:02:00',
  'motivoRechazo': motivo,
  'trabajadorId': 5,
  'trabajadorNombre': 'Marcelo Sepúlveda',
  'trabajadorRut': '17.930.556-9',
  'herramientaId': 8,
  'herramientaNombre': 'Taladro percutor 800 W',
  'resueltoPorId': resueltoPor == null ? null : 9,
  'resueltoPorNombre': resueltoPor,
};

class _Bodeguero extends SesionController {
  @override
  Future<SesionUsuario?> build() async => const SesionUsuario(
    token: 't',
    usuarioId: 9,
    nombre: 'Jorge Reyes',
    rol: 'BODEGUERO',
    empresaId: 1,
  );
}

/// La cola de bodega como la lleva el servidor: lo rechazado sale de las
/// pendientes. `falla` simula que otro bodeguero se adelantó o que el servidor
/// se cayó; en el caso de "ya resuelta", la solicitud además ya no está.
class _SolicitudesFalsas implements SolicitudesApi {
  final materiales = <SolicitudMaterial>[
    SolicitudMaterial.desdeJson(_jsonMaterial()),
  ];
  final herramientas = <SolicitudHerramienta>[
    SolicitudHerramienta.desdeJson(_jsonHerramienta()),
  ];

  /// Lo que se envió: `(id, motivo, clave)`.
  final rechazosMaterial = <(int, String, String?)>[];
  final rechazosHerramienta = <(int, String, String?)>[];

  Object? falla;

  /// Cuántas veces se pidió la cola de material.
  int cargas = 0;

  @override
  Future<List<SolicitudMaterial>> materialesPorObra(
    int obraId, {
    bool soloPendientes = true,
  }) async {
    cargas++;
    return materiales.where((s) => s.pendiente).toList();
  }

  @override
  Future<List<SolicitudHerramienta>> herramientasPorObra(
    int obraId, {
    bool soloPendientes = true,
  }) async => herramientas.where((s) => s.pendiente).toList();

  @override
  Future<SolicitudMaterial> rechazarMaterial(
    int solicitudId, {
    required String motivo,
    String? clave,
  }) async {
    rechazosMaterial.add((solicitudId, motivo, clave));
    if (falla != null) {
      final e = falla!;
      // "Ya resuelta": mientras tanto, otro bodeguero la resolvió.
      if (e is ApiException && e.yaEstabaHecho) {
        materiales
          ..clear()
          ..add(
            SolicitudMaterial.desdeJson(
              _jsonMaterial(estado: 'APROBADA', resueltoPor: 'Otro Bodeguero'),
            ),
          );
      }
      throw e;
    }
    final resuelta = SolicitudMaterial.desdeJson(
      _jsonMaterial(
        estado: 'RECHAZADA',
        motivo: motivo,
        resueltoPor: 'Jorge Reyes',
      ),
    );
    materiales
      ..clear()
      ..add(resuelta);
    return resuelta;
  }

  @override
  Future<SolicitudHerramienta> rechazarHerramienta(
    int solicitudId, {
    required String motivo,
    String? clave,
  }) async {
    rechazosHerramienta.add((solicitudId, motivo, clave));
    if (falla != null) throw falla!;
    final resuelta = SolicitudHerramienta.desdeJson(
      _jsonHerramienta(
        estado: 'RECHAZADA',
        motivo: motivo,
        resueltoPor: 'Jorge Reyes',
      ),
    );
    herramientas
      ..clear()
      ..add(resuelta);
    return resuelta;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Monta la cola de solicitudes de la obra.
Future<_SolicitudesFalsas> _montarCola(
  WidgetTester tester, {
  _SolicitudesFalsas? api,
}) async {
  final falsas = api ?? _SolicitudesFalsas();
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: sinReintentos,
      overrides: [
        sesionProvider.overrideWith(_Bodeguero.new),
        solicitudesApiProvider.overrideWithValue(falsas),
        solicitudesMaterialProvider.overrideWith(
          (ref) => ref.watch(solicitudesApiProvider).materialesPorObra(3),
        ),
        solicitudesHerramientaProvider.overrideWith(
          (ref) => ref.watch(solicitudesApiProvider).herramientasPorObra(3),
        ),
        pedidosEspecialesObraProvider.overrideWith((ref) async => const []),
        catalogoProvider.overrideWith(
          (ref) async => const [
            MaterialObra(
              id: 2,
              sku: 'VOL-ST-10',
              codigoBarra: null,
              nombre: 'Volcanita ST 10 mm',
              categoria: 'VOLCANITA',
              precioUnitario: 5980,
              stockMinimo: 40,
            ),
          ],
        ),
        stockPorMaterialProvider.overrideWith(
          (ref) => const AsyncValue.data({2: 100.0}),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 780),
            textScaler: TextScaler.linear(1.3),
          ),
          child: const PantallaSolicitudesObra(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return falsas;
}

/// Toca «Rechazar» de la primera fila visible y espera la hoja del motivo.
Future<void> _abrirHoja(WidgetTester tester) async {
  final boton = find.widgetWithText(OutlinedButton, 'Rechazar');
  await tester.ensureVisible(boton.first);
  await tester.tap(boton.first);
  await tester.pumpAndSettle();
}

Future<void> _enviar(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Rechazar solicitud'));
  await tester.tap(find.text('Rechazar solicitud'));
  await tester.pumpAndSettle();
}

const _errorSinMotivo =
    'Escribe el motivo: es lo único que el trabajador va a ver.';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_CL');
    await cargarInter();
  });

  group('Rechazar con motivo (B13)', () {
    testWidgets('la hoja pide el motivo y no manda nada si está vacío', (
      tester,
    ) async {
      final api = await _montarCola(tester);
      await _abrirHoja(tester);

      expect(find.text('Rechazar Volcanita ST 10 mm'), findsOneWidget);
      await _enviar(tester);

      expect(api.rechazosMaterial, isEmpty);
      expect(find.text(_errorSinMotivo), findsOneWidget);
      // La hoja sigue abierta para corregirlo.
      expect(find.text('Motivo del rechazo'), findsOneWidget);
    });

    testWidgets('un motivo de solo espacios tampoco se envía', (tester) async {
      final api = await _montarCola(tester);
      await _abrirHoja(tester);

      await tester.enterText(find.byType(TextFormField), '     ');
      await _enviar(tester);

      expect(api.rechazosMaterial, isEmpty);
      expect(find.text(_errorSinMotivo), findsOneWidget);
    });

    testWidgets('con motivo lo envía recortado y refresca la cola', (
      tester,
    ) async {
      final api = await _montarCola(tester);
      final cargasAntes = api.cargas;
      await _abrirHoja(tester);

      await tester.enterText(find.byType(TextFormField), '  $_motivo  ');
      await _enviar(tester);

      expect(api.rechazosMaterial, hasLength(1));
      final (id, motivo, clave) = api.rechazosMaterial.single;
      expect(id, 1);
      expect(motivo, _motivo);
      expect(clave, isNotEmpty, reason: 'viaja con clave de idempotencia');

      // La hoja se cierra, avisa y la cola se vuelve a pedir sin la solicitud.
      expect(find.text('Motivo del rechazo'), findsNothing);
      expect(find.text('Solicitud rechazada'), findsOneWidget);
      expect(api.cargas, greaterThan(cargasAntes));
      expect(find.text('Volcanita ST 10 mm'), findsNothing);
    });

    testWidgets('un motivo frecuente llena el campo y se puede enviar tal '
        'cual', (tester) async {
      final api = await _montarCola(tester);
      await _abrirHoja(tester);

      await tester.tap(find.text('No hay stock suficiente'));
      await tester.pumpAndSettle();
      await _enviar(tester);

      expect(api.rechazosMaterial.single.$2, 'No hay stock suficiente');
    });

    testWidgets('un error del servidor se muestra en la hoja y deja '
        'reintentar con la misma clave', (tester) async {
      final api = _SolicitudesFalsas()
        ..falla = const ApiException(500, 'No pudimos rechazar. Reintenta.');
      await _montarCola(tester, api: api);
      await _abrirHoja(tester);

      await tester.enterText(find.byType(TextFormField), _motivo);
      await _enviar(tester);

      expect(find.text('No pudimos rechazar. Reintenta.'), findsOneWidget);
      expect(find.text('Motivo del rechazo'), findsOneWidget);

      api.falla = null;
      await _enviar(tester);

      expect(api.rechazosMaterial, hasLength(2));
      // Mismo motivo → misma clave: si el primer intento sí llegó, el servidor
      // no rechaza dos veces.
      expect(api.rechazosMaterial[0].$3, api.rechazosMaterial[1].$3);
      expect(find.text('Solicitud rechazada'), findsOneWidget);
    });

    testWidgets('el campo no deja pasar de los 500 caracteres que acepta el '
        'servidor', (tester) async {
      final api = await _montarCola(tester);
      await _abrirHoja(tester);

      await tester.enterText(find.byType(TextFormField), 'x' * 600);
      await _enviar(tester);

      // Se corta al escribir: no se manda un motivo que el servidor rechazaría
      // con un 400 después de que el bodeguero ya lo escribió entero.
      expect(api.rechazosMaterial.single.$2, hasLength(500));
    });

    testWidgets('el rechazo de una herramienta exige motivo igual', (
      tester,
    ) async {
      final api = await _montarCola(tester);
      // Las herramientas van debajo de los materiales: se rechaza la última.
      final botones = find.widgetWithText(OutlinedButton, 'Rechazar');
      await tester.ensureVisible(botones.last);
      await tester.tap(botones.last);
      await tester.pumpAndSettle();

      expect(find.text('Rechazar Taladro percutor 800 W'), findsOneWidget);
      await _enviar(tester);
      expect(api.rechazosHerramienta, isEmpty);
      expect(find.text(_errorSinMotivo), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), _motivo);
      await _enviar(tester);

      expect(api.rechazosHerramienta.single.$2, _motivo);
    });
  });

  group('Ya resuelta (RN-07)', () {
    testWidgets('un 409 YA_RESUELTA cierra la hoja, lo dice y recarga la '
        'cola', (tester) async {
      final api = _SolicitudesFalsas()..falla = _yaResuelta;
      await _montarCola(tester, api: api);
      final cargasAntes = api.cargas;
      await _abrirHoja(tester);

      await tester.enterText(find.byType(TextFormField), _motivo);
      await _enviar(tester);

      // No es un error que corregir: otro bodeguero ya la resolvió.
      expect(find.text('Motivo del rechazo'), findsNothing);
      expect(
        find.text('La solicitud ya fue resuelta. La cola ya está al día.'),
        findsOneWidget,
      );
      // La cola se pidió de nuevo y ya no la ofrece para rechazar.
      expect(api.cargas, greaterThan(cargasAntes));
      expect(find.text('Volcanita ST 10 mm'), findsNothing);
    });

    testWidgets('no la rechaza dos veces: un solo intento', (tester) async {
      final api = _SolicitudesFalsas()..falla = _yaResuelta;
      await _montarCola(tester, api: api);
      await _abrirHoja(tester);

      await tester.enterText(find.byType(TextFormField), _motivo);
      await _enviar(tester);

      expect(api.rechazosMaterial, hasLength(1));
    });
  });

  group('Lo que ve el trabajador (E7)', () {
    Future<void> montarFila(WidgetTester tester, MiSolicitud s) async {
      // Si antes se montó la cola, se la desmonta: otro `ProviderScope` en el
      // mismo lugar sería una actualización, y no admite otros overrides.
      await tester.pumpWidget(const SizedBox());
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: sinReintentos,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: SingleChildScrollView(child: FilaMiSolicitud(solicitud: s)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('una solicitud de material rechazada muestra quién y por qué', (
      tester,
    ) async {
      final rechazada = SolicitudMaterial.desdeJson(
        _jsonMaterial(
          estado: 'RECHAZADA',
          motivo: _motivo,
          resueltoPor: 'Jorge Reyes',
        ),
      );

      await montarFila(tester, MiSolicitud.deMaterial(rechazada, unidad: 'pl'));

      expect(find.text('Rechazado'), findsOneWidget);
      expect(find.text('Jorge Reyes: “$_motivo”'), findsOneWidget);
    });

    testWidgets('una de herramienta también', (tester) async {
      final rechazada = SolicitudHerramienta.desdeJson(
        _jsonHerramienta(
          estado: 'RECHAZADA',
          motivo: 'Está en mantención hasta el lunes',
          resueltoPor: 'Jorge Reyes',
        ),
      );

      await montarFila(tester, MiSolicitud.deHerramienta(rechazada));

      expect(
        find.text('Jorge Reyes: “Está en mantención hasta el lunes”'),
        findsOneWidget,
      );
    });

    testWidgets('lo que bodega acaba de rechazar es lo que el trabajador lee', (
      tester,
    ) async {
      // De punta a punta: el motivo que se escribe en la hoja es el que sale
      // del servidor en la solicitud del trabajador.
      final api = await _montarCola(tester);
      await _abrirHoja(tester);
      await tester.enterText(find.byType(TextFormField), _motivo);
      await _enviar(tester);

      final lista = api.materiales.single;
      await montarFila(tester, MiSolicitud.deMaterial(lista, unidad: 'pl'));

      expect(find.text('Jorge Reyes: “$_motivo”'), findsOneWidget);
    });

    testWidgets('una rechazada sin motivo no inventa uno', (tester) async {
      final rechazada = SolicitudMaterial.desdeJson(
        _jsonMaterial(estado: 'RECHAZADA', resueltoPor: 'Jorge Reyes'),
      );

      await montarFila(tester, MiSolicitud.deMaterial(rechazada, unidad: 'pl'));

      expect(find.textContaining('“'), findsNothing);
    });
  });
}
