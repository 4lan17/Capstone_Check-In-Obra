import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/limitador_de_frecuencia.dart';

/// Cómo se identifica la app ante OpenStreetMap. Sus políticas de uso exigen un
/// User-Agent propio —el de Dio por defecto está bloqueado— y no llevan datos
/// personales: dice qué aplicación es, no quién la usa.
///
/// Solo ASCII: `dart:io` rechaza con `FormatException` una cabecera con tildes
/// y la petición ni siquiera sale.
const userAgentDeLaApp =
    'CheckInObra/1.0 (aplicacion movil de gestion de obras)';

/// Un resultado de la búsqueda de direcciones.
class Direccion {
  const Direccion({
    required this.nombre,
    required this.latitud,
    required this.longitud,
  });

  /// La dirección completa, como la escribe Nominatim.
  final String nombre;
  final double latitud;
  final double longitud;
}

/// Convierte un texto en lugares con coordenadas.
abstract class Geocodificador {
  /// Una lista vacía si no hay resultados. Un fallo de red sube como
  /// `DioException`: la pantalla distingue "no hay" de "no se pudo buscar".
  Future<List<Direccion>> buscar(String texto);
}

/// Busca en Nominatim, el buscador de OpenStreetMap.
///
/// Cumple su política de uso: solo se llama cuando el usuario **envía** la
/// búsqueda —nada de autocompletar—, a lo más una solicitud por segundo y con
/// un User-Agent identificable.
class GeocodificadorNominatim implements Geocodificador {
  GeocodificadorNominatim({Dio? dio, LimitadorDeFrecuencia? limitador})
    : _dio = dio ?? Dio(),
      _limitador = limitador ?? LimitadorDeFrecuencia();

  final Dio _dio;
  final LimitadorDeFrecuencia _limitador;

  static const _url = 'https://nominatim.openstreetmap.org/search';
  static const _maximoDeResultados = 5;

  @override
  Future<List<Direccion>> buscar(String texto) async {
    final q = texto.trim();
    if (q.isEmpty) return const [];

    final respuesta = await _limitador.ejecutar(
      () => _dio.get<dynamic>(
        _url,
        queryParameters: {
          'format': 'jsonv2',
          'q': q,
          'countrycodes': 'cl',
          'limit': _maximoDeResultados,
        },
        options: Options(
          headers: {'User-Agent': userAgentDeLaApp, 'Accept-Language': 'es'},
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      ),
    );

    final datos = respuesta.data;
    if (datos is! List) return const [];
    return [
      for (final d in datos)
        if (d is Map<String, dynamic>) ?_leer(d),
    ];
  }

  /// `null` si no trae coordenadas utilizables: se descarta en vez de romper
  /// toda la lista por un resultado raro.
  static Direccion? _leer(Map<String, dynamic> d) {
    final lat = double.tryParse('${d['lat']}');
    final lon = double.tryParse('${d['lon']}');
    final nombre = d['display_name'] as String?;
    if (lat == null || lon == null || nombre == null) return null;
    return Direccion(nombre: nombre, latitud: lat, longitud: lon);
  }
}

final geocodificadorProvider = Provider<Geocodificador>(
  (ref) => GeocodificadorNominatim(),
);
