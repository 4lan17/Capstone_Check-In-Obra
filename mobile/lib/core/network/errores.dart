import 'package:dio/dio.dart';

import '../../data/api/auth_api.dart';

/// Traduce cualquier fallo a un mensaje que le sirva a quien está en obra.
///
/// Un "connection error" pelado no le dice nada a un bodeguero con guantes.
/// Las causas reales en esta app son siempre las mismas pocas, así que se
/// nombran directamente.
String mensajeDeError(Object error) {
  if (error is ApiException) return error.mensaje;

  if (error is DioException) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'El servidor no respondió a tiempo. Revisa la señal e inténtalo de nuevo.',
      DioExceptionType.connectionError =>
        'No hay conexión con el servidor. Verifica que estés en la red de la obra.',
      DioExceptionType.badCertificate =>
        'El certificado del servidor no es válido.',
      DioExceptionType.cancel => 'La operación se canceló.',
      _ => error.message ?? 'Fallo de red',
    };
  }

  return 'Ocurrió un error inesperado.';
}
