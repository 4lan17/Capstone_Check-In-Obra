import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'app_config.dart';

/// Fijación de certificado (*certificate pinning*), opcional.
///
/// Sin ella, la app confía en cualquier certificado que el teléfono acepte:
/// una autoridad instalada en el equipo o comprometida basta para leer el PIN
/// y el JWT en una red hostil. Con ella, la app solo habla con un servidor que
/// presente un certificado de huella conocida.
///
/// Se activa **solo** al compilar con
/// `--dart-define=API_CERT_SHA256=<hex>` —varias huellas separadas por coma,
/// para poder rotar el certificado sin dejar a nadie fuera—. Sin la variable no
/// hace nada: el desarrollo y el emulador siguen igual.
///
/// La huella es el SHA-256 del certificado en DER, que es lo que imprime
/// `openssl x509 -in cert.pem -noout -fingerprint -sha256`.
class FijacionCertificado {
  const FijacionCertificado._(this._huellas);

  final Set<String> _huellas;

  /// Las huellas de la definición, o `null` si no hay ninguna (variable
  /// ausente o vacía). Una huella mal formada lanza [ConfiguracionInvalida].
  static FijacionCertificado? desde(String? definicion) {
    if (definicion == null) return null;
    final partes = definicion
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (partes.isEmpty) return null;
    return FijacionCertificado._({for (final p in partes) _normalizar(p)});
  }

  static final _hex64 = RegExp(r'^[0-9a-f]{64}$');

  /// Quita los dos puntos de `openssl` y pasa a minúsculas.
  static String _normalizar(String huella) {
    final limpia = huella.replaceAll(':', '').toLowerCase();
    if (!_hex64.hasMatch(limpia)) {
      throw const ConfiguracionInvalida(
        'API_CERT_SHA256 tiene una huella mal formada. Cada huella es el '
        'SHA-256 del certificado: 64 dígitos hexadecimales, con o sin ":". '
        'Para varias, sepáralas con coma.',
      );
    }
    return limpia;
  }

  /// ¿El SHA-256 de este certificado (en DER) es una de las huellas fijadas?
  bool acepta(Uint8List certificadoDer) =>
      _huellas.contains(sha256.convert(certificadoDer).toString());

  /// Lo que se le pregunta a un certificado que presenta el servidor: que su
  /// huella sea una de las fijadas **y** que esté vigente.
  ///
  /// Como la fijación reemplaza a la validación normal, la vigencia se revisa
  /// acá: un certificado vencido con la huella correcta no debe servir.
  bool aceptaCertificado(X509Certificate certificado, {DateTime? ahora}) {
    final t = ahora ?? DateTime.now();
    if (t.isBefore(certificado.startValidity) ||
        t.isAfter(certificado.endValidity)) {
      return false;
    }
    return acepta(certificado.der);
  }

  /// Un cliente que decide **en el apretón de manos TLS**, antes de enviar
  /// nada. Sin raíces de confianza, todo certificado cuenta como "no
  /// confiable" y pasa por `badCertificateCallback`, donde solo entra el que
  /// tiene una huella fijada.
  ///
  /// Se hace así y no con `validateCertificate` de Dio porque ese se evalúa
  /// después de enviar la petición: un servidor falso ya habría recibido el
  /// PIN cuando la app descubriera que no es el verdadero.
  HttpClient crearHttpClient() =>
      HttpClient(context: SecurityContext(withTrustedRoots: false))
        ..idleTimeout = const Duration(seconds: 3)
        ..badCertificateCallback = (certificado, host, puerto) =>
            aceptaCertificado(certificado);
}
