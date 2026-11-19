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
  ApiClient({
    Dio? dio,
    SesionStorage? storage,
    void Function()? alExpirar,
    void Function()? alDebeCambiarClave,
  }) : dio = dio ?? _crearDio() {
    if (storage != null) {
      this.dio.interceptors.add(
        _InterceptorToken(storage, alExpirar, alDebeCambiarClave),
      );
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
  _InterceptorToken(this._storage, this._alExpirar, this._alDebeCambiarClave);

  final SesionStorage _storage;
  final void Function()? _alExpirar;
  final void Function()? _alDebeCambiarClave;

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
    // Cuenta con clave provisoria: el servidor responde 403 a todo salvo al
    // cambio de clave. No es un "sin permiso" que mostrar como error, sino una
    // orden de llevar a la persona a cambiarla.
    if (response.statusCode == 403 && !esAuth && llevabaToken) {
      final cuerpo = response.data;
      if (cuerpo is Map && cuerpo['codigo'] == 'DEBE_CAMBIAR_PIN') {
        _alDebeCambiarClave?.call();
      }
    }
    handler.next(response);
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // `/api/auth/pin` es la única ruta de auth que va autenticada: cambia la
    // clave de quien tiene la sesión.
    if (!options.path.startsWith('/api/auth') ||
        options.path == '/api/auth/pin') {
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
    alDebeCambiarClave: () =>
        ref.read(sesionProvider.notifier).exigirCambioDeClave(),
  ),
);

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(apiClientProvider)),
);
