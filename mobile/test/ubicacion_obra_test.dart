import 'dart:async';
import 'dart:convert';

import 'package:checkinobra_mobile/core/sin_reintentos.dart';
import 'package:checkinobra_mobile/core/theme/app_theme.dart';
import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/data/api/dominio_api.dart';
import 'package:checkinobra_mobile/data/api/geocodificador.dart';
import 'package:checkinobra_mobile/data/modelos/obra.dart';
import 'package:checkinobra_mobile/features/obra/mapa/pantalla_ubicacion_obra.dart';
import 'package:checkinobra_mobile/features/obra/mapa/proveedor_de_teselas.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fuentes.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _Teselas extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_png);
}

const _quilicura = Direccion(
  nombre: 'Avenida Los Almendros 1240, Quilicura, Región Metropolitana',
  latitud: -33.363,
  longitud: -70.744,
);
const _colina = Direccion(
  nombre: 'Los Almendros, Colina, Región Metropolitana',
  latitud: -33.2,
  longitud: -70.67,
);

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
  jefeTerrenoNombre: null,
  jefeTerrenoRut: null,
  latitud: latitud,
  longitud: longitud,
);

/// Anota cada búsqueda y responde lo que se le diga; con [esperar] se queda
/// "buscando" hasta que se complete.
class _GeocodificadorFalso implements Geocodificador {
  _GeocodificadorFalso({this.resultados = const [_quilicura, _colina]});

  List<Direccion> resultados;
  Object? falla;
  Completer<List<Direccion>>? esperar;
  final busquedas = <String>[];

  @override
  Future<List<Direccion>> buscar(String texto) async {
    busquedas.add(texto);
    if (esperar != null) return esperar!.future;
    if (falla != null) throw falla!;
    return resultados;
  }
}

class _ObrasFalsas implements ObrasApi {
  final guardadas = <(int, double, double)>[];
  Object? falla;
  Completer<Obra>? esperar;

  @override
  Future<Obra> actualizarUbicacion(
    int obraId, {
    required double latitud,
    required double longitud,
    String? clave,
  }) async {
    guardadas.add((obraId, latitud, longitud));
    if (esperar != null) return esperar!.future;
    if (falla != null) throw falla!;
    return Obra(
      id: obraId,
      nombre: 'Los Almendros · Torre B',
      cliente: 'Inmobiliaria Vista Norte',
      ubicacion: 'Quilicura',
      estado: 'ACTIVA',
      jefeTerrenoNombre: null,
      jefeTerrenoRut: null,
      latitud: latitud,
      longitud: longitud,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _sinRed = DioException(
  requestOptions: RequestOptions(path: '/'),
  type: DioExceptionType.connectionError,
);

/// Monta la pantalla como se llega a ella: empujada encima de otra, para poder
/// ver que al guardar se cierra.
Future<void> _montar(
  WidgetTester tester, {
  Obra? obra,
  required _GeocodificadorFalso geocodificador,
  required _ObrasFalsas obras,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final laObra = obra ?? _obra();
  await tester.pumpWidget(
    ProviderScope(
      retry: sinReintentos,
      overrides: [
        proveedorDeTeselasProvider.overrideWith((ref) => _Teselas()),
        geocodificadorProvider.overrideWithValue(geocodificador),
        obrasApiProvider.overrideWithValue(obras),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PantallaUbicacionObra(obra: laObra),
                  ),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

Future<void> _buscar(WidgetTester tester, String texto) async {
  await tester.enterText(
    find.byKey(const ValueKey('busqueda-direccion')),
    texto,
  );
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Finder get _usar => find.text('Usar esta ubicación');

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_CL');
    await cargarInter();
  });

  group('Al abrir', () {
    testWidgets('muestra la obra, el mapa bajo un pin fijo y la ubicación '
        'actual con sus coordenadas', (tester) async {
      await _montar(
        tester,
        geocodificador: _GeocodificadorFalso(),
        obras: _ObrasFalsas(),
      );

      expect(find.text('Ubicación de la obra'), findsOneWidget);
      expect(find.text('Los Almendros · Torre B'), findsOneWidget);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byKey(const ValueKey('pin-fijo')), findsOneWidget);
      expect(find.text('-33,36300 · -70,74400'), findsOneWidget);
      expect(find.text('Av. Los Almendros 1240, Quilicura'), findsOneWidget);
      expect(find.text('© OpenStreetMap'), findsOneWidget);
    });

    testWidgets('una obra sin ubicación parte de Santiago', (tester) async {
      await _montar(
        tester,
        obra: _obra(latitud: null, longitud: null),
        geocodificador: _GeocodificadorFalso(),
        obras: _ObrasFalsas(),
      );

      expect(find.text('-33,44890 · -70,66930'), findsOneWidget);
    });

    testWidgets('no busca nada por sí sola', (tester) async {
      final geo = _GeocodificadorFalso();
      await _montar(tester, geocodificador: geo, obras: _ObrasFalsas());

      expect(geo.busquedas, isEmpty);
    });
  });

  group('Búsqueda de dirección', () {
    testWidgets('escribir no busca: solo al enviar (nada de autocompletar)', (
      tester,
    ) async {
      final geo = _GeocodificadorFalso();
      await _montar(tester, geocodificador: geo, obras: _ObrasFalsas());

      await tester.enterText(
        find.byKey(const ValueKey('busqueda-direccion')),
        'Av. Los Alm',
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.enterText(
        find.byKey(const ValueKey('busqueda-direccion')),
        'Av. Los Almendros 1240',
      );
      await tester.pump(const Duration(seconds: 3));

      expect(geo.busquedas, isEmpty);
    });

    testWidgets('enviar busca una vez y lista los resultados', (tester) async {
      final geo = _GeocodificadorFalso();
      await _montar(tester, geocodificador: geo, obras: _ObrasFalsas());

      await _buscar(tester, 'Los Almendros');

      expect(geo.busquedas, ['Los Almendros']);
      expect(find.text(_quilicura.nombre), findsOneWidget);
      expect(find.text(_colina.nombre), findsOneWidget);
    });

    testWidgets('el botón de la lupa también envía la búsqueda', (
      tester,
    ) async {
      final geo = _GeocodificadorFalso();
      await _montar(tester, geocodificador: geo, obras: _ObrasFalsas());

      await tester.enterText(
        find.byKey(const ValueKey('busqueda-direccion')),
        'Quilicura',
      );
      await tester.tap(find.byTooltip('Buscar dirección'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(geo.busquedas, ['Quilicura']);
    });

    testWidgets('mientras busca lo dice', (tester) async {
      final geo = _GeocodificadorFalso()..esperar = Completer();
      await _montar(tester, geocodificador: geo, obras: _ObrasFalsas());

      await _buscar(tester, 'Quilicura');

      expect(find.text('Buscando…'), findsOneWidget);

      geo.esperar!.complete([_quilicura]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Buscando…'), findsNothing);
      expect(find.text(_quilicura.nombre), findsOneWidget);
    });

    testWidgets('un texto en blanco no busca', (tester) async {
      final geo = _GeocodificadorFalso();
      await _montar(tester, geocodificador: geo, obras: _ObrasFalsas());

      await _buscar(tester, '    ');

      expect(geo.busquedas, isEmpty);
    });

    testWidgets('sin resultados lo dice con claridad', (tester) async {
      final geo = _GeocodificadorFalso(resultados: const []);
      await _montar(tester, geocodificador: geo, obras: _ObrasFalsas());

      await _buscar(tester, 'zzzz');

      expect(
        find.textContaining('No encontramos esa dirección'),
        findsOneWidget,
      );
    });

    testWidgets('un error de red lo dice y permite reintentar', (tester) async {
      final geo = _GeocodificadorFalso()..falla = _sinRed;
      await _montar(tester, geocodificador: geo, obras: _ObrasFalsas());

      await _buscar(tester, 'Quilicura');
      expect(find.textContaining('No pudimos buscar'), findsOneWidget);

      geo.falla = null;
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(geo.busquedas, ['Quilicura', 'Quilicura']);
      expect(find.text(_quilicura.nombre), findsOneWidget);
    });

    testWidgets('elegir un resultado mueve el pin y las coordenadas', (
      tester,
    ) async {
      final geo = _GeocodificadorFalso();
      await _montar(
        tester,
        obra: _obra(latitud: null, longitud: null),
        geocodificador: geo,
        obras: _ObrasFalsas(),
      );
      await _buscar(tester, 'Los Almendros');

      await tester.tap(find.text(_colina.nombre));
      await tester.pumpAndSettle();

      expect(find.text('-33,20000 · -70,67000'), findsOneWidget);
      expect(find.text(_colina.nombre), findsOneWidget);
      // La lista se recoge: ya se eligió.
      expect(find.text(_quilicura.nombre), findsNothing);
    });

    testWidgets('mover el mapa bajo el pin cambia las coordenadas', (
      tester,
    ) async {
      await _montar(
        tester,
        geocodificador: _GeocodificadorFalso(),
        obras: _ObrasFalsas(),
      );
      expect(find.text('-33,36300 · -70,74400'), findsOneWidget);

      await tester.drag(find.byType(FlutterMap), const Offset(-120, 0));
      await tester.pumpAndSettle();

      expect(find.text('-33,36300 · -70,74400'), findsNothing);
      // Se movió hacia el este: la longitud sube (menos negativa).
      final texto = tester
          .widgetList<Text>(find.textContaining(' · -70,'))
          .map((t) => t.data!)
          .single;
      final lon = double.parse(texto.split(' · ').last.replaceAll(',', '.'));
      expect(lon, greaterThan(-70.744));
    });

    testWidgets('al mover el mapa a mano, la dirección elegida deja de '
        'afirmarse', (tester) async {
      final geo = _GeocodificadorFalso();
      await _montar(tester, geocodificador: geo, obras: _ObrasFalsas());
      await _buscar(tester, 'Los Almendros');
      await tester.tap(find.text(_colina.nombre));
      await tester.pumpAndSettle();
      expect(find.text(_colina.nombre), findsOneWidget);

      await tester.drag(find.byType(FlutterMap), const Offset(80, 40));
      await tester.pumpAndSettle();

      expect(find.text(_colina.nombre), findsNothing);
      expect(find.text('Punto marcado en el mapa'), findsOneWidget);
    });
  });

  group('Usar esta ubicación', () {
    testWidgets('guarda las coordenadas del pin, cierra y avisa', (
      tester,
    ) async {
      final obras = _ObrasFalsas();
      await _montar(
        tester,
        geocodificador: _GeocodificadorFalso(),
        obras: obras,
      );

      await tester.tap(_usar);
      await tester.pumpAndSettle();

      expect(obras.guardadas, hasLength(1));
      final (id, lat, lon) = obras.guardadas.single;
      expect(id, 3);
      expect(lat, closeTo(-33.363, 0.0001));
      expect(lon, closeTo(-70.744, 0.0001));
      expect(find.byType(PantallaUbicacionObra), findsNothing);
      expect(find.text('Ubicación guardada'), findsOneWidget);
    });

    testWidgets('guarda lo que se eligió en la búsqueda', (tester) async {
      final obras = _ObrasFalsas();
      await _montar(
        tester,
        geocodificador: _GeocodificadorFalso(),
        obras: obras,
      );
      await _buscar(tester, 'Los Almendros');
      await tester.tap(find.text(_colina.nombre));
      await tester.pumpAndSettle();

      await tester.tap(_usar);
      await tester.pumpAndSettle();

      final (_, lat, lon) = obras.guardadas.single;
      expect(lat, closeTo(-33.2, 0.0001));
      expect(lon, closeTo(-70.67, 0.0001));
    });

    testWidgets('mientras guarda se ve y no se puede mandar dos veces', (
      tester,
    ) async {
      final obras = _ObrasFalsas()..esperar = Completer();
      await _montar(
        tester,
        geocodificador: _GeocodificadorFalso(),
        obras: obras,
      );

      await tester.tap(_usar);
      await tester.pump();
      expect(find.text('Guardando…'), findsOneWidget);
      await tester.tap(find.text('Guardando…'), warnIfMissed: false);
      await tester.pump();

      expect(obras.guardadas, hasLength(1));
    });

    testWidgets('una obra cerrada responde 409: se muestra el mensaje y se '
        'queda en la pantalla', (tester) async {
      final obras = _ObrasFalsas()
        ..falla = const ApiException(
          409,
          'La obra está cerrada: ya no se puede cambiar su ubicación.',
        );
      await _montar(
        tester,
        geocodificador: _GeocodificadorFalso(),
        obras: obras,
      );

      await tester.tap(_usar);
      await tester.pumpAndSettle();

      expect(
        find.text('La obra está cerrada: ya no se puede cambiar su ubicación.'),
        findsOneWidget,
      );
      expect(find.byType(PantallaUbicacionObra), findsOneWidget);
      expect(find.text('Ubicación guardada'), findsNothing);
    });

    testWidgets('sin red al guardar lo dice y deja reintentar', (tester) async {
      final obras = _ObrasFalsas()..falla = _sinRed;
      await _montar(
        tester,
        geocodificador: _GeocodificadorFalso(),
        obras: obras,
      );

      await tester.tap(_usar);
      await tester.pumpAndSettle();
      expect(find.textContaining('No hay conexión'), findsOneWidget);

      obras.falla = null;
      await tester.tap(_usar);
      await tester.pumpAndSettle();

      expect(obras.guardadas, hasLength(2));
      expect(find.byType(PantallaUbicacionObra), findsNothing);
    });
  });

  group('Zoom', () {
    testWidgets('acercar y alejar tienen su botón', (tester) async {
      await _montar(
        tester,
        geocodificador: _GeocodificadorFalso(),
        obras: _ObrasFalsas(),
      );

      expect(find.byTooltip('Acercar'), findsOneWidget);
      expect(find.byTooltip('Alejar'), findsOneWidget);

      await tester.tap(find.byTooltip('Acercar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Alejar'));
      await tester.pumpAndSettle();

      // El pin se queda donde estaba: acercar no mueve el punto marcado.
      expect(find.text('-33,36300 · -70,74400'), findsOneWidget);
    });
  });
}
