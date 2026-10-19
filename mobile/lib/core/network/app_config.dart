import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuración leída desde `mobile/.env`.
///
/// Ese archivo NO está versionado (lo ignora `.gitignore`), porque la URL
/// depende de la máquina de cada quien. Si falta, la app no revienta: arranca
/// igual y lo informa en pantalla, que es más útil que un crash en el arranque.
abstract final class AppConfig {
  static bool _envCargado = false;

  static Future<void> cargar() async {
    try {
      await dotenv.load(fileName: '.env');
      _envCargado = true;
    } catch (_) {
      // Sin .env seguimos con los valores por defecto de abajo.
      _envCargado = false;
    }
  }

  /// `true` si se pudo leer el archivo `.env`.
  static bool get envCargado => _envCargado;

  /// URL fijada al compilar con `--dart-define=API_BASE_URL=...`. Gana sobre
  /// el `.env`: la usa `scripts/levantar.sh --telefono`, que conecta el
  /// teléfono por `adb reverse` y necesita `localhost` sin reescribir el `.env`
  /// de nadie.
  static const _apiDefinidaAlCompilar = String.fromEnvironment('API_BASE_URL');

  /// URL base de la API. El valor por defecto apunta al emulador de Android:
  /// 10.0.2.2 es como el emulador alcanza el localhost del computador.
  static String get apiBaseUrl {
    if (_apiDefinidaAlCompilar.isNotEmpty) return _apiDefinidaAlCompilar;
    if (!_envCargado) return 'http://10.0.2.2:8081';
    final valor = dotenv.env['API_BASE_URL'];
    if (valor == null || valor.isEmpty) return 'http://10.0.2.2:8081';
    return valor;
  }
}
