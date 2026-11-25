import 'dart:convert';

import 'package:checkinobra_mobile/core/limitador_de_frecuencia.dart';
import 'package:checkinobra_mobile/data/api/geocodificador.dart';
import 'package:checkinobra_mobile/data/modelos/obra.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _obraJson({Object? latitud, Object? longitud}) => {
  'id': 3,
  'nombre': 'Los Almendros · Torre B',
  'cliente': 'Inmobiliaria Vista Norte',
  'ubicacion': 'Quilicura',
  'estado': 'ACTIVA',
  'jefeTerrenoNombre': null,
  'jefeTerrenoRut': null,
  'latitud': latitud,
  'longitud': longitud,
};

/// Lo que Nominatim responde a una búsqueda, con las dos coordenadas como
/// texto, que es como las manda.
const _respuesta = [
  {
    'place_id': 1,
    'lat': '-33.3630000',
    'lon': '-70.7440000',
    'display_name':
        'Avenida Los Almendros 1240, Quilicura, Región Metropolitana',
    'name': 'Avenida Los Almendros',
  },
  {
    'place_id': 2,
    'lat': '-33.4000',
    'lon': '-70.6000',
    'display_name': 'Los Almendros, Providencia, Región Metropolitana',
  },
];

/// Un servidor de mentira que anota cada petición que le llega.
class _Servidor implements HttpClientAdapter {
  _Servidor({this.estado = 200, this.cuerpo = _respuesta, this.error});

  final int estado;
  final Object cuerpo;
  final DioException? error;
  final peticiones = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    peticiones.add(options);
    if (error != null) throw error!.copyWith(requestOptions: options);
    return ResponseBody.fromString(
      jsonEncode(cuerpo),
      estado,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

GeocodificadorNominatim _geocodificador(
  _Servidor servidor, {
  LimitadorDeFrecuencia? limitador,
}) {
  final dio = Dio()..httpClientAdapter = servidor;
  return GeocodificadorNominatim(
    dio: dio,
    limitador:
        limitador ??
        LimitadorDeFrecuencia(
          intervalo: Duration.zero,
          ahora: DateTime.now,
          dormir: (_) async {},
        ),
  );
}

void main() {
  group('Obra', () {
    test('lee la ubicación cuando la trae', () {
      final o = Obra.desdeJson(_obraJson(latitud: -33.363, longitud: -70.744));

      expect(o.latitud, -33.363);
      expect(o.longitud, -70.744);
      expect(o.tieneUbicacion, isTrue);
    });

    test('sin coordenadas (nulas) no tiene ubicación', () {
      final o = Obra.desdeJson(_obraJson());

      expect(o.latitud, isNull);
      expect(o.longitud, isNull);
      expect(o.tieneUbicacion, isFalse);
    });

    test('los enteros del JSON también valen como coordenadas', () {
      final o = Obra.desdeJson(_obraJson(latitud: -33, longitud: -70));

      expect(o.latitud, -33.0);
      expect(o.tieneUbicacion, isTrue);
    });

    test('una sola coordenada no es una ubicación', () {
      final o = Obra.desdeJson(_obraJson(latitud: -33.3));

      expect(o.tieneUbicacion, isFalse);
    });

    test('un servidor que aún no manda los campos no rompe nada', () {
      final json = _obraJson()
        ..remove('latitud')
        ..remove('longitud');

      expect(Obra.desdeJson(json).tieneUbicacion, isFalse);
    });
  });

  group('Limitador de frecuencia', () {
    late DateTime ahora;
    late List<Duration> esperas;

    LimitadorDeFrecuencia crear() => LimitadorDeFrecuencia(
      intervalo: const Duration(seconds: 1),
      ahora: () => ahora,
      dormir: (d) async {
        esperas.add(d);
        ahora = ahora.add(d);
      },
    );

    setUp(() {
      ahora = DateTime(2026, 11, 23, 10);
      esperas = [];
    });

    test('la primera solicitud sale al tiro', () async {
      final limitador = crear();

      await limitador.ejecutar(() async => 1);

      expect(esperas, isEmpty);
    });

    test('la segunda espera lo que falta para completar el segundo', () async {
      final limitador = crear();
      await limitador.ejecutar(() async => 1);

      ahora = ahora.add(const Duration(milliseconds: 300));
      await limitador.ejecutar(() async => 2);

      expect(esperas, [const Duration(milliseconds: 700)]);
    });

    test('si ya pasó el segundo, no espera', () async {
      final limitador = crear();
      await limitador.ejecutar(() async => 1);

      ahora = ahora.add(const Duration(seconds: 2));
      await limitador.ejecutar(() async => 2);

      expect(esperas, isEmpty);
    });

    test('varias a la vez salen en fila, de a una por segundo', () async {
      final limitador = crear();
      final salieron = <DateTime>[];

      await Future.wait([
        for (var i = 0; i < 3; i++)
          limitador.ejecutar(() async => salieron.add(ahora)),
      ]);

      expect(salieron.length, 3);
      expect(salieron[1].difference(salieron[0]), const Duration(seconds: 1));
      expect(salieron[2].difference(salieron[1]), const Duration(seconds: 1));
    });

    test('un fallo no traba a las que siguen', () async {
      final limitador = crear();

      await expectLater(
        limitador.ejecutar<void>(() async => throw StateError('falló')),
        throwsStateError,
      );
      final r = await limitador.ejecutar(() async => 'sigue');

      expect(r, 'sigue');
    });
  });

  group('Búsqueda de direcciones (Nominatim)', () {
    test('pide solo en Chile, 5 resultados, en jsonv2', () async {
      final servidor = _Servidor();

      await _geocodificador(servidor).buscar('Av. Los Almendros 1240');

      final p = servidor.peticiones.single;
      expect(p.uri.origin, 'https://nominatim.openstreetmap.org');
      expect(p.uri.path, '/search');
      expect(p.uri.queryParameters, {
        'format': 'jsonv2',
        'q': 'Av. Los Almendros 1240',
        'countrycodes': 'cl',
        'limit': '5',
      });
    });

    test('se identifica con un User-Agent propio', () async {
      final servidor = _Servidor();

      await _geocodificador(servidor).buscar('Quilicura');

      final agente = servidor.peticiones.single.headers['User-Agent'] as String;
      expect(agente, contains('CheckInObra'));
      // Dio por defecto manda "Dart/…": OSM lo bloquea. Que sea el nuestro.
      expect(agente, isNot(contains('Dart')));
    });

    test('todas las cabeceras son ASCII: dart:io rechaza el resto antes de '
        'enviar', () async {
      // El adaptador de mentira no valida cabeceras, pero el de verdad sí: un
      // User-Agent con tildes lanza FormatException y la búsqueda nunca sale.
      final servidor = _Servidor();

      await _geocodificador(servidor).buscar('Quilicura');

      final imprimibleAscii = RegExp(r'^[\x20-\x7E]*$');
      for (final cabecera in servidor.peticiones.single.headers.entries) {
        expect(
          imprimibleAscii.hasMatch('${cabecera.value}'),
          isTrue,
          reason: '${cabecera.key}: ${cabecera.value}',
        );
      }
      expect(imprimibleAscii.hasMatch(userAgentDeLaApp), isTrue);
    });

    test('lee nombre y coordenadas, que Nominatim manda como texto', () async {
      final r = await _geocodificador(_Servidor()).buscar('Los Almendros');

      expect(r, hasLength(2));
      expect(
        r.first.nombre,
        'Avenida Los Almendros 1240, Quilicura, Región Metropolitana',
      );
      expect(r.first.latitud, -33.363);
      expect(r.first.longitud, -70.744);
      expect(r.last.latitud, -33.4);
    });

    test('sin resultados devuelve una lista vacía', () async {
      final r = await _geocodificador(_Servidor(cuerpo: const []))
          .buscar('zzzz');

      expect(r, isEmpty);
    });

    test('ignora lo que viene sin coordenadas válidas', () async {
      final r = await _geocodificador(
        _Servidor(
          cuerpo: const [
            {'lat': 'no', 'lon': '-70', 'display_name': 'roto'},
            {'lat': '-33.1', 'lon': '-70.1', 'display_name': 'bueno'},
          ],
        ),
      ).buscar('x');

      expect(r.map((d) => d.nombre), ['bueno']);
    });

    test('un texto en blanco no llama a nadie', () async {
      final servidor = _Servidor();

      final r = await _geocodificador(servidor).buscar('   ');

      expect(r, isEmpty);
      expect(servidor.peticiones, isEmpty);
    });

    test('recorta el texto antes de buscar', () async {
      final servidor = _Servidor();

      await _geocodificador(servidor).buscar('  Quilicura  ');

      expect(servidor.peticiones.single.uri.queryParameters['q'], 'Quilicura');
    });

    test(
      'dos búsquedas seguidas respetan el límite de una por segundo',
      () async {
        var ahora = DateTime(2026, 11, 23, 10);
        final esperas = <Duration>[];
        final servidor = _Servidor();
        final geo = _geocodificador(
          servidor,
          limitador: LimitadorDeFrecuencia(
            intervalo: const Duration(seconds: 1),
            ahora: () => ahora,
            dormir: (d) async {
              esperas.add(d);
              ahora = ahora.add(d);
            },
          ),
        );

        await geo.buscar('Quilicura');
        await geo.buscar('Colina');

        expect(servidor.peticiones, hasLength(2));
        expect(esperas, [const Duration(seconds: 1)]);
      },
    );

    test('un fallo de red sube como excepción de Dio', () async {
      final servidor = _Servidor(
        error: DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.connectionError,
        ),
      );

      await expectLater(
        _geocodificador(servidor).buscar('Quilicura'),
        throwsA(isA<DioException>()),
      );
    });

    test('un 429 (demasiadas solicitudes) también sube como error', () async {
      final servidor = _Servidor(estado: 429, cuerpo: const []);

      await expectLater(
        _geocodificador(servidor).buscar('Quilicura'),
        throwsA(isA<DioException>()),
      );
    });
  });
}
