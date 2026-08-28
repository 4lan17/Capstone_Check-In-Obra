import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/auth_api.dart';
import '../storage/sesion_storage.dart';
import 'app_config.dart';

/// Cliente HTTP contra la API de Check-In-Obra.
///
/// Los timeouts son cortos a propósito: en terreno, esperar 30 segundos a que
/// una petición muera es peor que fallar rápido y reintentar.
class ApiClient {
  ApiClient({Dio? dio, SesionStorage? storage}) : dio = dio ?? _crearDio() {
    if (storage != null) {
      this.dio.interceptors.add(_InterceptorToken(storage));
    }
  }

  static Dio _crearDio() => Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      sendTimeout: const Duration(seconds: 8),
      contentType: Headers.jsonContentType,
      // No lanzar excepción por 4xx: los manejamos nosotros para
      // distinguir "credenciales malas" de "no hay red".
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  final Dio dio;

  String get baseUrl => dio.options.baseUrl;
}

/// Adjunta el JWT a cada petición, salvo a las de `/api/auth` — pedir el
/// token mandando el token no tiene sentido.
class _InterceptorToken extends Interceptor {
  _InterceptorToken(this._storage);

  final SesionStorage _storage;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!options.path.startsWith('/api/auth')) {
      final token = await _storage.leerToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }
}

final sesionStorageProvider = Provider<SesionStorage>((ref) => SesionStorage());

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(storage: ref.watch(sesionStorageProvider)),
);

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(apiClientProvider)),
);
