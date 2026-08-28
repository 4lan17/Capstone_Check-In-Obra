import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/app_config.dart';
import '../../data/api/auth_api.dart';

/// Resultado de la prueba de conexión contra el backend.
class ResultadoConexion {
  const ResultadoConexion({
    required this.ok,
    required this.titulo,
    required this.detalle,
    required this.url,
    this.comoArreglarlo,
    this.sesion,
    this.latenciaMs,
  });

  final bool ok;
  final String titulo;
  final String detalle;
  final String url;

  /// Qué hacer para resolverlo. Solo se llena cuando falla y sabemos la causa.
  final String? comoArreglarlo;
  final SesionUsuario? sesion;
  final int? latenciaMs;
}

/// Credenciales del administrador semilla que crea la migración `V2`.
/// Sirven solo para verificar la conexión en local.
const _emailSemilla = 'admin@arauco-ltda.cl';
const _pinSemilla = '0000';

class DiagnosticoConexion extends AsyncNotifier<ResultadoConexion?> {
  @override
  Future<ResultadoConexion?> build() async => null; // Estado inicial: sin probar.

  Future<void> probar() async {
    state = const AsyncValue.loading();
    final cliente = ref.read(apiClientProvider);
    final api = ref.read(authApiProvider);
    final url = cliente.baseUrl;
    final reloj = Stopwatch()..start();

    try {
      final sesion = await api.login(email: _emailSemilla, pin: _pinSemilla);
      reloj.stop();
      state = AsyncValue.data(ResultadoConexion(
        ok: true,
        titulo: 'Conexión establecida',
        detalle: 'El backend respondió y autenticó al usuario semilla.',
        url: url,
        sesion: sesion,
        latenciaMs: reloj.elapsedMilliseconds,
      ));
    } on DioException catch (e) {
      reloj.stop();
      state = AsyncValue.data(_desdeDioException(e, url));
    } on ApiException catch (e) {
      reloj.stop();
      state = AsyncValue.data(ResultadoConexion(
        ok: false,
        titulo: 'El servidor respondió, pero rechazó la petición',
        detalle: e.mensaje,
        url: url,
        comoArreglarlo: e.statusCode == 400
            ? 'La red funciona. Revisa que la migración V2 haya corrido:\n'
                'docker compose logs backend | grep Flyway'
            : null,
      ));
    } catch (e) {
      reloj.stop();
      state = AsyncValue.data(ResultadoConexion(
        ok: false,
        titulo: 'Error inesperado',
        detalle: e.toString(),
        url: url,
      ));
    }
  }

  /// Traduce el fallo de red a una causa concreta. Un "connection error" sin
  /// más contexto no le sirve a nadie: en esta app las causas reales son
  /// siempre las mismas cuatro.
  ResultadoConexion _desdeDioException(DioException e, String url) {
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        ResultadoConexion(
          ok: false,
          titulo: 'El servidor no respondió a tiempo',
          detalle: 'Se agotaron los 8 segundos de espera.',
          url: url,
          comoArreglarlo:
              'Suele ser el firewall del computador descartando el paquete '
              'en silencio. En Ubuntu:\n'
              'sudo ufw allow from 192.168.1.0/24 to any port 8081 proto tcp',
        ),
      DioExceptionType.connectionError => ResultadoConexion(
          ok: false,
          titulo: 'No se pudo alcanzar el servidor',
          detalle: 'No hay ruta hacia $url.',
          url: url,
          comoArreglarlo: 'Revisa, en este orden:\n'
              '1. El backend está arriba — docker compose ps\n'
              '2. El teléfono y el computador están en la MISMA red WiFi\n'
              '3. La IP del .env es la actual — cambia al cambiar de red\n'
              '4. El firewall permite el puerto 8081',
        ),
      DioExceptionType.badCertificate => ResultadoConexion(
          ok: false,
          titulo: 'Certificado rechazado',
          detalle: 'El certificado TLS no es válido.',
          url: url,
          comoArreglarlo: 'En local la API va por HTTP, no HTTPS. '
              'Revisa que la URL del .env empiece con http://',
        ),
      _ => ResultadoConexion(
          ok: false,
          titulo: 'Fallo de red',
          detalle: e.message ?? e.type.name,
          url: url,
        ),
    };
  }
}

final diagnosticoConexionProvider =
    AsyncNotifierProvider<DiagnosticoConexion, ResultadoConexion?>(
  DiagnosticoConexion.new,
);

/// Expone si se pudo leer el `.env`, para avisarlo en pantalla.
final envCargadoProvider = Provider<bool>((ref) => AppConfig.envCargado);
