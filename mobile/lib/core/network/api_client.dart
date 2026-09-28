import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/auth_api.dart';
import '../storage/sesion_storage.dart';
import '../../features/auth/sesion_controller.dart';
import 'app_config.dart';

/// Cliente HTTP contra la API de Check-In-Obra.
///
/// Los timeouts son cortos a propósito: en terreno, esperar 30 segundos a que
/// una petición muera es peor que fallar rápido y reintentar.
class ApiClient {
  ApiClient({Dio? dio, SesionStorage? storage, void Function()? alExpirar})
    : dio = dio ?? _crearDio() {
    if (storage != null) {
      this.dio.interceptors.add(_InterceptorToken(storage, alExpirar));
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
///
/// También detecta el token vencido. El JWT guardado se usa para entrar sin
/// credenciales al abrir la app, pero expira: sin esto se entraba igual y cada
/// pantalla mostraba "tu sesión expiró" sin ofrecer salida. Un 401 fuera de
/// `/api/auth` cierra la sesión, y quien está en bodega vuelve a la pantalla
/// del PIN con su usuario recordado.
class _InterceptorToken extends Interceptor {
  _InterceptorToken(this._storage, this._alExpirar);

  final SesionStorage _storage;
  final void Function()? _alExpirar;

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final esAuth = response.requestOptions.path.startsWith('/api/auth');
    final llevabaToken = response.requestOptions.headers.containsKey(
      'Authorization',
    );
    if (response.statusCode == 401 && !esAuth && llevabaToken) {
      _alExpirar?.call();
    }
    handler.next(response);
  }

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
  (ref) => ApiClient(
    storage: ref.watch(sesionStorageProvider),
    // Se lee al momento del 401, no al construir: el controlador de sesión
    // depende de este cliente para el login.
    alExpirar: () => ref.read(sesionProvider.notifier).expirar(),
  ),
);

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(apiClientProvider)),
);
