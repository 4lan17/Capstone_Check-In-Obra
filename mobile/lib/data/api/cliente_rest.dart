import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import 'auth_api.dart';

/// Envoltorio sobre `dio` con el manejo de errores que ya usaba `AuthApi`,
/// factorizado para que cada API del dominio no lo repita.
///
/// `ApiClient` configura `validateStatus` para que los 4xx **no** lancen
/// excepción: llegan como respuesta normal. Eso es a propósito —permite
/// distinguir "el servidor dijo que no" de "no hubo servidor"— pero obliga a
/// revisar el código en cada llamada, que es justo lo que hace esta clase.
class ClienteRest {
  const ClienteRest(this._client);

  final ApiClient _client;

  Future<List<T>> lista<T>(
    String ruta,
    T Function(Map<String, dynamic>) desde, {
    Map<String, dynamic>? params,
  }) async {
    final r = await _client.dio.get<List<dynamic>>(
      ruta,
      queryParameters: params,
    );
    _exigirExito(r);
    return (r.data ?? const [])
        .map((e) => desde(e as Map<String, dynamic>))
        .toList();
  }

  Future<T> uno<T>(
    String ruta,
    T Function(Map<String, dynamic>) desde, {
    Map<String, dynamic>? params,
  }) async {
    final r = await _client.dio.get<Map<String, dynamic>>(
      ruta,
      queryParameters: params,
    );
    _exigirExito(r);
    return desde(r.data!);
  }

  /// Para los endpoints que devuelven un escalar suelto, como
  /// `GET /api/kardex/stock`.
  Future<double> numero(String ruta, {Map<String, dynamic>? params}) async {
    final r = await _client.dio.get<dynamic>(ruta, queryParameters: params);
    _exigirExito(r);
    return (r.data as num).toDouble();
  }

  Future<T> crear<T>(
    String ruta,
    Map<String, dynamic> cuerpo,
    T Function(Map<String, dynamic>) desde,
  ) async {
    final r = await _client.dio.post<Map<String, dynamic>>(ruta, data: cuerpo);
    _exigirExito(r);
    return desde(r.data!);
  }

  Future<List<T>> crearLista<T>(
    String ruta,
    Map<String, dynamic> cuerpo,
    T Function(Map<String, dynamic>) desde,
  ) async {
    final r = await _client.dio.post<List<dynamic>>(ruta, data: cuerpo);
    _exigirExito(r);
    return (r.data ?? const [])
        .map((e) => desde(e as Map<String, dynamic>))
        .toList();
  }

  Future<T> actualizar<T>(
    String ruta,
    Map<String, dynamic> cuerpo,
    T Function(Map<String, dynamic>) desde,
  ) async {
    final r = await _client.dio.put<Map<String, dynamic>>(ruta, data: cuerpo);
    _exigirExito(r);
    return desde(r.data!);
  }

  void _exigirExito(Response<dynamic> r) {
    final codigo = r.statusCode ?? 0;
    if (codigo >= 200 && codigo < 300) return;

    final cuerpo = r.data;
    final mensaje = cuerpo is Map && cuerpo['mensaje'] is String
        ? cuerpo['mensaje'] as String
        : _porDefecto(codigo);
    throw ApiException(codigo, mensaje);
  }

  /// El backend casi siempre manda un mensaje propio; esto cubre los casos en
  /// que no, traducido a lo que significa en esta app.
  String _porDefecto(int codigo) => switch (codigo) {
    400 => 'Los datos enviados no son válidos.',
    401 => 'Tu sesión expiró. Vuelve a entrar.',
    403 => 'Tu rol no permite esta acción.',
    404 => 'No se encontró lo que buscabas.',
    409 => 'La operación choca con el estado actual.',
    _ => 'El servidor respondió con código $codigo.',
  };
}
