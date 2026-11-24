import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:checkinobra_mobile/core/theme/app_theme.dart';
import 'package:checkinobra_mobile/data/modelos/obra.dart';
import 'package:checkinobra_mobile/features/obra/mapa/mapa_obra.dart';
import 'package:checkinobra_mobile/features/obra/mapa/proveedor_de_teselas.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'fuentes.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// Un servidor de tiles de mentira: anota cuántas veces se pide cada uno y a
/// qué hora, y cada prueba decide cuáles fallan.
class _Teselas extends TileProvider {
  _Teselas({required this.falla});

  /// `true` si ese tile falla en esa vuelta (1 = la primera vez que se pide).
  final bool Function(TileCoordinates tile, int vuelta) falla;

  final llamadas = <String, List<DateTime>>{};
  DateTime Function() ahora = DateTime.now;

  static String clave(TileCoordinates t) => '${t.z}/${t.x}/${t.y}';

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final k = clave(coordinates);
    final lista = llamadas.putIfAbsent(k, () => []);
    lista.add(ahora());
    return falla(coordinates, lista.length)
        ? _ImagenRota('$k#${lista.length}')
        : MemoryImage(_png);
  }
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

Obra _obra() => const Obra(
  id: 3,
  nombre: 'Los Almendros · Torre B',
  cliente: 'Vista Norte',
  ubicacion: 'Av. Los Almendros 1240, Quilicura',
  estado: 'ACTIVA',
  jefeTerrenoNombre: null,
  jefeTerrenoRut: null,
  latitud: -33.363,
  longitud: -70.744,
);

Future<_Teselas> _montar(
  WidgetTester tester, {
  required bool Function(TileCoordinates, int) falla,
  bool miniatura = false,
}) async {
  final teselas = _Teselas(falla: falla)
    ..ahora = () => tester.binding.clock.now();
  tester.view.physicalSize = const Size(390, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [proveedorDeTeselasProvider.overrideWith((ref) => teselas)],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MapaObra(obra: _obra(), miniatura: miniatura),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  return teselas;
}

Future<void> _pasan(WidgetTester tester, int segundos) async {
  for (var i = 0; i < segundos * 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// El proveedor de red de verdad (el que usa la app) hace E/S real —abre su
/// caché en disco—, que el reloj falso de `testWidgets` no hace avanzar.
Future<void> _dejarCorrerLaRed(WidgetTester tester) async {
  // Se alterna: un poco de tiempo real para que el disco responda y un cuadro
  // para que el reloj falso procese lo que respondió.
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

int _veces(_Teselas t, String clave) => t.llamadas[clave]?.length ?? 0;

void main() {
  setUpAll(() async {
    await cargarInter();
  });

  group('Un tile que no llega se reintenta', () {
    testWidgets('si en la segunda vuelta llega, el mapa queda completo y sin '
        'placeholder', (tester) async {
      // Todos fallan la primera vez que se piden y llegan a la segunda.
      final t = await _montar(tester, falla: (_, vuelta) => vuelta == 1);

      await _pasan(tester, 3);

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byKey(const ValueKey('pin-de-mapa')), findsOneWidget);
      expect(find.text('Av. Los Almendros 1240, Quilicura'), findsNothing);
      expect(t.llamadas, isNotEmpty);
      for (final k in t.llamadas.keys) {
        expect(_veces(t, k), 2, reason: 'el tile $k se pidió dos veces');
      }
    });

    testWidgets('espera 2 s antes del primer reintento y 4 s antes del '
        'segundo (espera creciente, sin ráfagas)', (tester) async {
      final t = await _montar(tester, falla: (_, _) => true);

      await _pasan(tester, 30);

      final k = t.llamadas.keys.first;
      final horas = t.llamadas[k]!;
      expect(horas, hasLength(3));
      final primera = horas[1].difference(horas[0]).inMilliseconds;
      final segunda = horas[2].difference(horas[1]).inMilliseconds;
      expect(primera, inInclusiveRange(1900, 2600));
      expect(segunda, inInclusiveRange(3900, 4600));
    });

    testWidgets('los reintentos son solo dos: después no pide nada más', (
      tester,
    ) async {
      final t = await _montar(tester, falla: (_, _) => true);

      await _pasan(tester, 12);
      final tras12 = {
        for (final e in t.llamadas.entries) e.key: e.value.length,
      };
      await _pasan(tester, 120);

      for (final e in t.llamadas.entries) {
        expect(e.value.length, 3, reason: '1 pedido + 2 reintentos: ${e.key}');
        expect(e.value.length, tras12[e.key]);
      }
    });

    testWidgets('si carga a la primera, no reintenta nada', (tester) async {
      final t = await _montar(tester, falla: (_, _) => false);

      await _pasan(tester, 20);

      for (final k in t.llamadas.keys) {
        expect(_veces(t, k), 1);
      }
      expect(find.byType(FlutterMap), findsOneWidget);
    });

    testWidgets('mientras reintenta sigue mostrando el mapa, no el '
        'placeholder', (tester) async {
      await _montar(tester, falla: (_, _) => true);

      await _pasan(tester, 3);

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.text('Av. Los Almendros 1240, Quilicura'), findsNothing);
    });

    testWidgets('si se va de la pantalla durante la espera, no queda nada '
        'pendiente', (tester) async {
      final t = await _montar(tester, falla: (_, _) => true);
      final antes = {for (final e in t.llamadas.entries) e.key: e.value.length};

      await tester.pumpWidget(const SizedBox());
      await _pasan(tester, 30);

      expect(tester.takeException(), isNull);
      for (final e in t.llamadas.entries) {
        expect(e.value.length, antes[e.key], reason: 'no pidió más: ${e.key}');
      }
    });
  });

  group('Cuándo se rinde y muestra el placeholder', () {
    testWidgets('la card (120 px) con todos los tiles caídos, después de '
        'reintentar', (tester) async {
      await _montar(tester, falla: (_, _) => true);

      await _pasan(tester, 10);

      expect(find.byType(FlutterMap), findsNothing);
      expect(find.byKey(const ValueKey('pin-de-mapa')), findsOneWidget);
      expect(find.text('Av. Los Almendros 1240, Quilicura'), findsOneWidget);
    });

    testWidgets('la card con UN solo tile caído sigue siendo un mapa (el '
        'resto se ve)', (tester) async {
      // Falla siempre el tile de la izquierda del centro; los demás cargan.
      // A zoom 16 (el de la card), la columna del centro es:
      final columnaDelCentro = ((-70.744 + 180) / 360 * 65536).floor();
      final filaDelCentro =
          ((1 -
                      math.log(
                            math.tan(-33.363 * math.pi / 180) +
                                1 / math.cos(-33.363 * math.pi / 180),
                          ) /
                          math.pi) /
                  2 *
                  65536)
              .floor();
      await _montar(
        tester,
        falla: (t, _) => t.x == columnaDelCentro - 1 && t.y == filaDelCentro,
      );

      await _pasan(tester, 10);

      expect(find.byType(FlutterMap), findsOneWidget);
    });

    testWidgets('la miniatura (64 px) se rinde con UN solo tile caído', (
      tester,
    ) async {
      // La miniatura cabe en uno o dos tiles: con uno que no llegue ya no hay
      // mapa que valga. Antes de este cambio, nunca llegaba al placeholder.
      await _montar(tester, falla: (_, _) => true, miniatura: true);

      await _pasan(tester, 10);

      expect(find.byType(FlutterMap), findsNothing);
      expect(find.byKey(const ValueKey('pin-de-mapa')), findsOneWidget);
      expect(tester.getSize(find.byType(MapaObra)), const Size(64, 64));
    });

    testWidgets('la miniatura cuyos tiles llegan en el reintento no se '
        'rinde', (tester) async {
      await _montar(tester, falla: (_, vuelta) => vuelta == 1, miniatura: true);

      await _pasan(tester, 10);

      expect(find.byType(FlutterMap), findsOneWidget);
    });
  });

  group('El cliente HTTP de los tiles', () {
    testWidgets('no se cierra cuando un mapa se destruye: los demás siguen '
        'pudiendo pedir tiles', (tester) async {
      final cliente = _ClienteDeMentira();
      // El proveedor de verdad guarda los tiles en el caché de la app, que en
      // el teléfono es un directorio del sistema: acá, uno temporal.
      final carpeta = Directory.systemTemp.createTempSync('teselas_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => carpeta.path,
          );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              null,
            );
        carpeta.deleteSync(recursive: true);
      });
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Widget mapa(bool visible) => ProviderScope(
        // El mismo contenedor entre los dos montajes, como en la app: el
        // proveedor de tiles vive más que cualquier mapa.
        key: const ValueKey('app'),
        overrides: [clienteHttpDeTeselasProvider.overrideWithValue(cliente)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: visible ? MapaObra(obra: _obra()) : const SizedBox(),
          ),
        ),
      );

      await tester.pumpWidget(mapa(true));
      await _dejarCorrerLaRed(tester);
      final primeras = cliente.peticiones;
      expect(primeras, greaterThan(0));

      // Se va de la pantalla: `TileLayer.dispose()` llama a
      // `TileProvider.dispose()`. Con un cliente propio del proveedor, eso lo
      // cerraba para todos.
      await tester.pumpWidget(mapa(false));
      await _dejarCorrerLaRed(tester);
      expect(cliente.cerrado, isFalse);

      // Vuelve (otro mapa): sus tiles tienen que poder pedirse.
      await tester.pumpWidget(mapa(true));
      await _dejarCorrerLaRed(tester);
      expect(cliente.cerrado, isFalse);
      expect(cliente.peticionesConClienteCerrado, 0);
    });

    test('se cierra al soltar el contenedor de la app', () {
      final cliente = _ClienteDeMentira();
      final c = ProviderContainer(
        overrides: [
          clienteHttpDeTeselasProvider.overrideWith((ref) {
            ref.onDispose(cliente.close);
            return cliente;
          }),
        ],
      );

      c.read(proveedorDeTeselasProvider);
      expect(cliente.cerrado, isFalse);
      c.dispose();

      expect(cliente.cerrado, isTrue);
    });

    test('un mismo cliente sirve a todos los mapas (una sola conexión '
        'reutilizada, como pide OSM)', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      expect(
        identical(
          c.read(clienteHttpDeTeselasProvider),
          c.read(clienteHttpDeTeselasProvider),
        ),
        isTrue,
      );
      expect(
        identical(
          c.read(proveedorDeTeselasProvider),
          c.read(proveedorDeTeselasProvider),
        ),
        isTrue,
      );
    });
  });
}

/// Responde un PNG a todo y avisa si se le pide algo después de cerrado.
class _ClienteDeMentira extends http.BaseClient {
  bool cerrado = false;
  int peticiones = 0;
  int peticionesConClienteCerrado = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    peticiones++;
    if (cerrado) {
      peticionesConClienteCerrado++;
      throw http.ClientException('Client closed', request.url);
    }
    return http.StreamedResponse(
      Stream.value(_png),
      200,
      headers: {'content-type': 'image/png'},
      request: request,
    );
  }

  @override
  void close() => cerrado = true;
}
