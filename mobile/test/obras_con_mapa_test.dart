import 'dart:convert';

import 'package:checkinobra_mobile/core/sin_reintentos.dart';
import 'package:checkinobra_mobile/core/theme/app_theme.dart';
import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/data/modelos/detalle_obra.dart';
import 'package:checkinobra_mobile/data/modelos/obra.dart';
import 'package:checkinobra_mobile/features/admin/pantalla_detalle_obra.dart';
import 'package:checkinobra_mobile/features/admin/pantalla_obras.dart';
import 'package:checkinobra_mobile/features/auth/sesion_controller.dart';
import 'package:checkinobra_mobile/features/obra/mapa/mapa_obra.dart';
import 'package:checkinobra_mobile/features/obra/mapa/pantalla_ubicacion_obra.dart';
import 'package:checkinobra_mobile/features/obra/mapa/proveedor_de_teselas.dart';
import 'package:checkinobra_mobile/features/obra/obra_activa.dart';
import 'package:checkinobra_mobile/features/obra/pantalla_elegir_obra.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fixtures_obra.dart';
import 'fuentes.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _TeselasQueCargan extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_png);
}

class _TeselasQueFallan extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _ImagenRota('${coordinates.x}/${coordinates.y}/${coordinates.z}');
}

class _ImagenRota extends ImageProvider<_ImagenRota> {
  const _ImagenRota(this.clave);

  final String clave;

  @override
  Future<_ImagenRota> obtainKey(ImageConfiguration configuration) =>
      Future.value(this);

  @override
  ImageStreamCompleter loadImage(
    _ImagenRota key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    Future<ImageInfo>.error(Exception('Sin red')),
  );

  @override
  bool operator ==(Object other) =>
      other is _ImagenRota && other.clave == clave;

  @override
  int get hashCode => clave.hashCode;
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

Obra _obra(
  int id,
  String nombre, {
  String estado = 'ACTIVA',
  double? latitud,
  double? longitud,
}) => Obra(
  id: id,
  nombre: nombre,
  cliente: 'Inmobiliaria Vista Norte',
  ubicacion: 'Quilicura',
  estado: estado,
  jefeTerrenoNombre: 'Camila Bravo',
  jefeTerrenoRut: '12.345.678-5',
  latitud: latitud,
  longitud: longitud,
);

final _conMapa = _obra(1, 'Torre B', latitud: -33.363, longitud: -70.744);
final _sinUbicacion = _obra(2, 'Torre C');
final _cerrada = _obra(
  3,
  'Mirador Sur',
  estado: 'CERRADA',
  latitud: -33.41,
  longitud: -70.6,
);

final _detalle = DetalleObra.desdeJson(detalleDePrueba());

Future<void> _montar(
  WidgetTester tester,
  Widget pantalla, {
  required List<Obra> obras,
  TileProvider? teselas,
  double alto = 1800,
}) async {
  tester.view.physicalSize = Size(390, alto);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: sinReintentos,
      overrides: [
        sesionProvider.overrideWith(_SesionAdmin.new),
        proveedorDeTeselasProvider.overrideWith(
          (ref) => teselas ?? _TeselasQueCargan(),
        ),
        todasLasObrasProvider.overrideWith((ref) async => obras),
        obrasActivasProvider.overrideWith(
          (ref) async => obras.where((o) => o.activa).toList(),
        ),
        detalleObraProvider.overrideWith((ref, id) async => _detalle),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(390, alto),
            textScaler: TextScaler.linear(1.3),
          ),
          child: pantalla,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Los tiles que no llegan se reintentan dos veces (a los 2 y 4 s) antes de
/// mostrar el placeholder: hay que dejar pasar ese tiempo.
Future<void> _esperarLosReintentos(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_CL');
    await cargarInter();
  });

  group('Admin › Obras', () {
    testWidgets('cada obra con ubicación lleva su franja de mapa de 120 px', (
      tester,
    ) async {
      await _montar(
        tester,
        const PantallaObras(),
        obras: [_conMapa, _sinUbicacion, _cerrada],
      );

      // La activa y la cerrada tienen coordenadas; la tercera no.
      expect(find.byType(FlutterMap), findsNWidgets(2));
      for (final mapa in tester.widgetList<MapaObra>(find.byType(MapaObra))) {
        expect(tester.getSize(find.byWidget(mapa)).height, 120);
      }
    });

    testWidgets('una obra sin coordenadas dice que falta y ofrece marcarla', (
      tester,
    ) async {
      await _montar(
        tester,
        const PantallaObras(),
        obras: [_conMapa, _sinUbicacion],
      );

      expect(find.text('Sin ubicación todavía'), findsOneWidget);
      expect(find.text('Marcar en el mapa'), findsOneWidget);
    });

    testWidgets('«Marcar en el mapa» abre la pantalla de ubicación de esa '
        'obra', (tester) async {
      await _montar(tester, const PantallaObras(), obras: [_sinUbicacion]);

      await tester.tap(find.text('Marcar en el mapa'));
      await tester.pumpAndSettle();

      expect(find.byType(PantallaUbicacionObra), findsOneWidget);
      expect(find.text('Torre C'), findsOneWidget);
    });

    testWidgets('tocar la card (no el mapa ni el botón) abre la ficha', (
      tester,
    ) async {
      await _montar(tester, const PantallaObras(), obras: [_conMapa]);

      await tester.tap(find.text('Torre B'));
      await tester.pumpAndSettle();

      expect(find.byType(PantallaDetalleObra), findsOneWidget);
    });

    testWidgets('una obra cerrada se ve en escala de grises y no se puede '
        'marcar', (tester) async {
      await _montar(
        tester,
        const PantallaObras(),
        obras: [
          _obra(3, 'Mirador Sur', estado: 'CERRADA'),
          _cerrada.copiaSinCoordenadas(),
        ],
      );

      expect(find.text('Marcar en el mapa'), findsNothing);
    });

    testWidgets('la obra cerrada con mapa va en grises', (tester) async {
      await _montar(tester, const PantallaObras(), obras: [_conMapa, _cerrada]);

      expect(find.byKey(const ValueKey('mapa-en-grises')), findsOneWidget);
    });

    testWidgets('«Nueva obra» es una barra fija sobre la navegación, no un '
        'botón flotante', (tester) async {
      await _montar(tester, const PantallaObras(), obras: [_conMapa]);

      expect(find.byType(FloatingActionButton), findsNothing);
      final boton = find.widgetWithText(FilledButton, 'Nueva obra');
      expect(boton, findsOneWidget);
      // Pegada al borde de abajo.
      expect(tester.getBottomLeft(boton).dy, greaterThan(1700));
    });

    testWidgets('«Nueva obra» no se va con la lista al desplazar', (
      tester,
    ) async {
      final muchas = [
        for (var i = 1; i <= 8; i++)
          _obra(i, 'Obra $i', latitud: -33.36 - i / 100, longitud: -70.74),
      ];
      await _montar(tester, const PantallaObras(), obras: muchas, alto: 800);
      final antes = tester.getTopLeft(find.text('Nueva obra'));

      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.getTopLeft(find.text('Nueva obra')), antes);
    });

    testWidgets('«Nueva obra» abre el formulario', (tester) async {
      await _montar(tester, const PantallaObras(), obras: [_conMapa]);

      await tester.tap(find.text('Nueva obra'));
      await tester.pumpAndSettle();

      expect(find.byType(PantallaNuevaObra), findsOneWidget);
    });

    testWidgets('sin red las cards no se rompen: el pin y la dirección en '
        'texto', (tester) async {
      await _montar(
        tester,
        const PantallaObras(),
        obras: [_conMapa],
        teselas: _TeselasQueFallan(),
      );
      await _esperarLosReintentos(tester);

      expect(find.byType(FlutterMap), findsNothing);
      expect(find.byKey(const ValueKey('pin-de-mapa')), findsOneWidget);
      expect(find.text('Quilicura'), findsWidgets);
      expect(find.text('Torre B'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con la lista vacía sigue el mismo camino de siempre', (
      tester,
    ) async {
      await _montar(tester, const PantallaObras(), obras: const []);

      expect(find.text('Todavía no hay obras'), findsOneWidget);
    });
  });

  group('Elegir obra', () {
    testWidgets('cada obra lleva una miniatura de mapa de 64 px', (
      tester,
    ) async {
      await _montar(
        tester,
        const PantallaElegirObra(),
        obras: [_conMapa, _sinUbicacion],
      );

      final miniaturas = find.byType(MapaObra);
      expect(miniaturas, findsNWidgets(2));
      for (final m in tester.widgetList<MapaObra>(miniaturas)) {
        expect(tester.getSize(find.byWidget(m)), const Size(64, 64));
      }
      expect(find.byType(FlutterMap), findsOneWidget);
    });

    testWidgets('quien elige obra no ve el botón de marcarla', (tester) async {
      await _montar(tester, const PantallaElegirObra(), obras: [_sinUbicacion]);

      expect(find.text('Marcar en el mapa'), findsNothing);
      expect(find.text('Sin ubicación todavía'), findsNothing);
    });

    testWidgets('elegir una obra sigue funcionando', (tester) async {
      await _montar(tester, const PantallaElegirObra(), obras: [_conMapa]);

      expect(find.text('Torre B'), findsOneWidget);
      expect(find.text('Inmobiliaria Vista Norte'), findsOneWidget);
    });
  });
}

extension on Obra {
  /// La misma obra sin ubicación, para probar la cerrada sin mapa.
  Obra copiaSinCoordenadas() => Obra(
    id: id + 100,
    nombre: '$nombre sin mapa',
    cliente: cliente,
    ubicacion: ubicacion,
    estado: estado,
    jefeTerrenoNombre: jefeTerrenoNombre,
    jefeTerrenoRut: jefeTerrenoRut,
  );
}
