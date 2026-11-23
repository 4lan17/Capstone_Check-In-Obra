/// Refleja `POST /api/trabajadores/yo/credencial/codigo`: el código de vida
/// corta con que el trabajador se identifica en bodega.
///
/// Reemplaza al UUID fijo de antes. Un código que vale dos minutos no sirve
/// fotografiado ni compartido: quien lo captura lo tiene vencido para cuando
/// llega al mesón.
class CodigoCredencial {
  const CodigoCredencial({
    required this.codigo,
    required this.expiraEn,
    required this.vigenciaSegundos,
  });

  /// Ocho caracteres sin ambiguos (sin 0/O ni 1/I), sin distinguir mayúsculas.
  /// Es lo que lleva el QR, en texto plano.
  final String codigo;

  /// Cuándo vence, según el reloj del servidor. La app **no** lo compara con
  /// el del teléfono —un reloj desajustado mostraría como vencido un código
  /// bueno—: cuenta la vigencia desde que lo recibió.
  final DateTime expiraEn;

  /// Cuánto vale desde que se emite.
  final int vigenciaSegundos;

  /// `K7M2-9QXP`: en dos grupos de cuatro, que es como se dicta y se tipea.
  String get agrupado => codigo.length <= 4
      ? codigo
      : '${codigo.substring(0, 4)}-${codigo.substring(4)}';

  factory CodigoCredencial.desdeJson(Map<String, dynamic> j) =>
      CodigoCredencial(
        codigo: j['codigo'] as String,
        expiraEn: DateTime.parse(j['expiraEn'] as String),
        vigenciaSegundos: j['vigenciaSegundos'] as int,
      );
}

/// Lo que escribe o pega el bodeguero, llevado a como el servidor lo guarda:
/// sin espacios ni guiones y en mayúsculas. `k7m2-9qxp` y `K7M29QXP` son el
/// mismo código.
String normalizarCodigoCredencial(String texto) =>
    texto.replaceAll(RegExp(r'[\s-]+'), '').toUpperCase();
