import 'dart:convert';

import 'package:checkinobra_mobile/core/theme/app_theme.dart';
import 'package:checkinobra_mobile/data/api/cliente_rest.dart';
import 'package:checkinobra_mobile/data/api/dominio_api.dart';
import 'package:checkinobra_mobile/data/modelos/obra.dart';
import 'package:checkinobra_mobile/features/obra/mapa/mapa_obra.dart';
import 'package:checkinobra_mobile/features/obra/mapa/proveedor_de_teselas.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fuentes.dart';

/// Un PNG de 1×1: lo que "carga" un tile cuando hay red.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// Tiles que cargan.
class _TeselasQueCargan extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_png);
}

/// Tiles que no llegan: lo que pasa sin señal.
class _TeselasQueFallan extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      _ImagenRota(coordinates.toString());
}

class _ImagenRota extends ImageProvider<_ImagenRota> {
  const _ImagenRota(this.clave);

  final String clave;

  @override
  Future<_ImagenRota> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

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

Obra _obra({
  double? latitud = -33.363,
  double? longitud = -70.744,
  String estado = 'ACTIVA',
}) => Obra(
  id: 3,
  nombre: 'Los Almendros · Torre B',
  cliente: 'Inmobiliaria Vista Norte',
  ubicacion: 'Av. Los Almendros 1240, Quilicura',
  estado: estado,
  jefeTerrenoNombre: 'Camila Bravo',
  jefeTerrenoRut: '12.345.678-5',
  latitud: latitud,
  longitud: longitud,
);

Future<void> _montar(
  WidgetTester tester,
  Widget mapa, {
  TileProvider? teselas,
}) async {
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        proveedorDeTeselasProvider.overrideWith(
          (ref) => teselas ?? _TeselasQueCargan(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: Center(child: mapa)),
      ),
    ),
  );
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
    await cargarInter();
  });

  group('Con ubicación', () {
    testWidgets('dibuja el mapa de OpenStreetMap con su pin', (tester) async {
      await _montar(tester, MapaObra(obra: _obra()));

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byKey(const ValueKey('pin-de-mapa')), findsOneWidget);
      expect(find.text('Sin ubicación todavía'), findsNothing);
    });

    testWidgets('la atribución de OpenStreetMap está siempre a la vista', (
      tester,
    ) async {
      await _montar(tester, MapaObra(obra: _obra()));

      expect(find.text('© OpenStreetMap'), findsOneWidget);
    });

    testWidgets('pide los tiles al servidor de OSM con un paquete '
        'identificable', (tester) async {
      await _montar(tester, MapaObra(obra: _obra()));

      final capa = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(
        capa.urlTemplate,
        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      );
      // `userAgentPackageName` no se guarda: flutter_map lo vuelca en la
      // cabecera User-Agent del proveedor, que es lo que ve el servidor.
      expect(
        capa.tileProvider.headers['User-Agent'],
        'flutter_map (cl.duocuc.checkinobra_mobile)',
      );
    });

    testWidgets('el mapa de la card no se mueve ni se acerca', (tester) async {
      await _montar(tester, MapaObra(obra: _obra()));

      final mapa = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(mapa.options.interactionOptions.flags, InteractiveFlag.none);
    });

    testWidgets('queda centrado en la obra', (tester) async {
      await _montar(tester, MapaObra(obra: _obra()));

      final mapa = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(mapa.options.initialCenter.latitude, -33.363);
      expect(mapa.options.initialCenter.longitude, -70.744);
    });

    testWidgets('mide 120 px de alto en la card', (tester) async {
      await _montar(tester, MapaObra(obra: _obra()));

      expect(tester.getSize(find.byType(MapaObra)).height, 120);
    });

    testWidgets('el mapa se anuncia al lector de pantalla', (tester) async {
      final handle = tester.ensureSemantics();
      await _montar(tester, MapaObra(obra: _obra()));

      expect(
        find.bySemanticsLabel('Mapa de Los Almendros · Torre B'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('una obra cerrada se ve en escala de grises, con pin gris', (
      tester,
    ) async {
      await _montar(tester, MapaObra(obra: _obra(estado: 'CERRADA')));

      expect(find.byKey(const ValueKey('mapa-en-grises')), findsOneWidget);
      final pin = tester.widget<PinDeMapa>(
        find.byKey(const ValueKey('pin-de-mapa')),
      );
      expect(pin.color, isNot(const Color(0xFFEA580C)));
    });

    testWidgets('una obra activa conserva el color y el pin naranja', (
      tester,
    ) async {
      await _montar(tester, MapaObra(obra: _obra()));

      expect(find.byKey(const ValueKey('mapa-en-grises')), findsNothing);
      final pin = tester.widget<PinDeMapa>(
        find.byKey(const ValueKey('pin-de-mapa')),
      );
      expect(pin.color, const Color(0xFFEA580C));
    });
  });

  group('Sin ubicación', () {
    testWidgets('dice que no hay y ofrece marcarla, a quien puede', (
      tester,
    ) async {
      var marcadas = 0;
      await _montar(
        tester,
        MapaObra(
          obra: _obra(latitud: null, longitud: null),
          alMarcar: () => marcadas++,
        ),
      );

      expect(find.text('Sin ubicación todavía'), findsOneWidget);
      expect(find.byType(FlutterMap), findsNothing);

      await tester.tap(find.text('Marcar en el mapa'));
      expect(marcadas, 1);
    });

    testWidgets('para quien no es admin, el placeholder no lleva botón', (
      tester,
    ) async {
      await _montar(
        tester,
        MapaObra(obra: _obra(latitud: null, longitud: null)),
      );

      expect(find.text('Sin ubicación todavía'), findsOneWidget);
      expect(find.text('Marcar en el mapa'), findsNothing);
    });

    testWidgets('una obra cerrada tampoco se puede marcar (el servidor '
        'respondería 409)', (tester) async {
      await _montar(
        tester,
        MapaObra(
          obra: _obra(latitud: null, longitud: null, estado: 'CERRADA'),
          alMarcar: () {},
        ),
      );

      expect(find.text('Sin ubicación todavía'), findsOneWidget);
      expect(find.text('Marcar en el mapa'), findsNothing);
    });

    testWidgets('no pide ni un tile', (tester) async {
      await _montar(
        tester,
        MapaObra(obra: _obra(latitud: null, longitud: null)),
      );

      expect(find.byType(TileLayer), findsNothing);
    });
  });

  group('Sin red', () {
    testWidgets('si los tiles no llegan, un placeholder con el pin y la '
        'dirección en texto', (tester) async {
      await _montar(
        tester,
        MapaObra(obra: _obra()),
        teselas: _TeselasQueFallan(),
      );
      await _esperarLosReintentos(tester);

      expect(find.byType(FlutterMap), findsNothing);
      expect(find.byKey(const ValueKey('pin-de-mapa')), findsOneWidget);
      expect(find.text('Av. Los Almendros 1240, Quilicura'), findsOneWidget);
      expect(find.text('Sin ubicación todavía'), findsNothing);
      // Nunca una card rota: ni excepciones ni recuadros de error.
      expect(tester.takeException(), isNull);
    });

    testWidgets('el placeholder sin red no lleva la atribución de un mapa que '
        'no se ve', (tester) async {
      await _montar(
        tester,
        MapaObra(obra: _obra()),
        teselas: _TeselasQueFallan(),
      );
      await _esperarLosReintentos(tester);

      expect(find.text('© OpenStreetMap'), findsNothing);
    });
  });

  group('Miniatura de 64 px', () {
    testWidgets('mide 64×64 y lleva la atribución abreviada', (tester) async {
      await _montar(tester, MapaObra(obra: _obra(), miniatura: true));

      expect(tester.getSize(find.byType(MapaObra)), const Size(64, 64));
      expect(find.text('© OSM'), findsOneWidget);
    });

    testWidgets('sin ubicación, solo el ícono: nunca un botón en 64 px', (
      tester,
    ) async {
      await _montar(
        tester,
        MapaObra(
          obra: _obra(latitud: null, longitud: null),
          miniatura: true,
          alMarcar: () {},
        ),
      );

      expect(tester.getSize(find.byType(MapaObra)), const Size(64, 64));
      expect(find.text('Marcar en el mapa'), findsNothing);
      expect(find.text('Sin ubicación todavía'), findsNothing);
      expect(find.byIcon(Icons.location_off_outlined), findsOneWidget);
    });
  });

  group('API de obras', () {
    test('actualizar la ubicación es PUT /api/obras/{id}/ubicacion', () async {
      final rest = _RestQueAnota();

      await ObrasApi(rest)
          .actualizarUbicacion(3, latitud: -33.363, longitud: -70.744);

      expect(rest.ruta, '/api/obras/3/ubicacion');
      expect(rest.cuerpo, {'latitud': -33.363, 'longitud': -70.744});
    });

    test('el alta acepta las coordenadas y, si no hay, no las manda', () async {
      final conCoordenadas = _RestQueAnota();
      await ObrasApi(conCoordenadas).crear(
        nombre: 'Torre B',
        cliente: 'Vista Norte',
        ubicacion: 'Quilicura',
        latitud: -33.363,
        longitud: -70.744,
      );
      expect(conCoordenadas.cuerpo, containsPair('latitud', -33.363));
      expect(conCoordenadas.cuerpo, containsPair('longitud', -70.744));

      final sin = _RestQueAnota();
      await ObrasApi(sin).crear(
        nombre: 'Torre B',
        cliente: 'Vista Norte',
        ubicacion: 'Quilicura',
      );
      expect(sin.cuerpo, isNot(contains('latitud')));
      expect(sin.cuerpo, isNot(contains('longitud')));
    });
  });
}

/// Anota la ruta y el cuerpo con que se escribe.
class _RestQueAnota implements ClienteRest {
  String? ruta;
  Object? cuerpo;

  static const _json = {
    'id': 3,
    'nombre': 'Torre B',
    'cliente': 'Vista Norte',
    'ubicacion': 'Quilicura',
    'estado': 'ACTIVA',
    'jefeTerrenoNombre': null,
    'jefeTerrenoRut': null,
  };

  @override
  Future<T> actualizar<T>(
    String ruta,
    Object? cuerpo,
    T Function(Map<String, dynamic>) desde, {
    String? clave,
  }) async {
    this.ruta = ruta;
    this.cuerpo = cuerpo;
    return desde(_json);
  }

  @override
  Future<T> crear<T>(
    String ruta,
    Object? cuerpo,
    T Function(Map<String, dynamic>) desde, {
    String? clave,
  }) async {
    this.ruta = ruta;
    this.cuerpo = cuerpo;
    return desde(_json);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
