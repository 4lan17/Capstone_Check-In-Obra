import 'package:intl/intl.dart';

/// Formato chileno para todo lo que se muestra: punto como separador de miles,
/// coma decimal. Un "1,240" en una pantalla de bodega chilena se lee como mil
/// doscientos cuarenta, no como uno coma dos.
abstract final class Formato {
  /// El símbolo se antepone a mano. `NumberFormat.currency` con `es_CL`
  /// devuelve "5.980 $" —símbolo al final, con espacio— y en Chile los precios
  /// se escriben "$5.980". El separador de miles sí lo pone el locale.
  static final _enteros = NumberFormat('#,##0', 'es_CL');

  static final _cantidad = NumberFormat('#,##0.##', 'es_CL');
  static final _hora = DateFormat('HH:mm', 'es_CL');
  static final _fechaCorta = DateFormat('dd MMM', 'es_CL');
  static final _fechaHora = DateFormat('dd MMM HH:mm', 'es_CL');

  static String pesos(double v) => '\$${_enteros.format(v)}';

  /// Cantidades de material: se muestran sin decimales cuando son enteras,
  /// porque "36 pl" se lee más rápido que "36,00 pl".
  static String cantidad(double v) => _cantidad.format(v);

  static String cantidadConSigno(double v) =>
      '${v > 0
          ? '+'
          : v < 0
          ? '−'
          : ''}${_cantidad.format(v.abs())}';

  static String hora(DateTime d) => _hora.format(d);

  static String fechaHora(DateTime d) => _fechaHora.format(d);

  /// "hoy 09:02", "ayer 15:41" o "22 ago" — como en el mockup del kardex.
  static String relativa(DateTime d) {
    final ahora = DateTime.now();
    final dia = DateTime(d.year, d.month, d.day);
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    final diferencia = hoy.difference(dia).inDays;
    if (diferencia == 0) return 'hoy ${_hora.format(d)}';
    if (diferencia == 1) return 'ayer ${_hora.format(d)}';
    return _fechaCorta.format(d);
  }

  /// Lee un número **tal como lo teclea alguien en Chile**.
  ///
  /// El caso difícil es el punto: en "5.980" separa miles y en "0.75" es
  /// decimal, y el teclado numérico de Android ofrece los dos signos sin
  /// distinguirlos. La regla es la misma que aplica el backend al leer una
  /// planilla ({@code Numeros.decimal}), para que el mismo texto signifique lo
  /// mismo tecleado que importado:
  ///
  /// - con coma, la coma es el decimal y el punto separa miles ("12.500,75");
  /// - con punto solo, separa miles **si** deja exactamente tres dígitos detrás
  ///   ("5.980" → 5980) y es decimal en cualquier otro caso ("0.75" → 0,75).
  ///
  /// Antes cada pantalla tenía su propia regla: la de movimiento leía "1.200"
  /// como 1,2 y la de aprobación leía "0.5" como 5. Son cantidades que van al
  /// kardex, así que un factor de mil o de diez ahí no se nota hasta el
  /// descuadre.
  static double? numero(String texto) {
    var limpio = texto.replaceAll(' ', '').replaceAll('\u00A0', '').trim();
    if (limpio.isEmpty) return null;

    if (limpio.contains(',')) {
      limpio = limpio.replaceAll('.', '').replaceAll(',', '.');
    } else {
      final ultimoPunto = limpio.lastIndexOf('.');
      final separadorDeMiles =
          ultimoPunto > 0 && limpio.length - ultimoPunto - 1 == 3;
      if (separadorDeMiles) limpio = limpio.replaceAll('.', '');
    }

    return double.tryParse(limpio);
  }

  /// "hace 2 h", "hace 14 h", "hace 3 d" — para la antigüedad de una alerta.
  static String antiguedad(DateTime d) {
    final minutos = DateTime.now().difference(d).inMinutes;
    if (minutos < 1) return 'recién';
    if (minutos < 60) return 'hace $minutos min';
    final horas = minutos ~/ 60;
    if (horas < 24) return 'hace $horas h';
    return 'hace ${horas ~/ 24} d';
  }
}
