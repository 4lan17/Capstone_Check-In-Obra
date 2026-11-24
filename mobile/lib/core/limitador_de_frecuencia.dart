import 'dart:async';

/// Deja pasar una tarea cada [intervalo], en fila.
///
/// Es lo que pide la política de uso de Nominatim: como máximo una solicitud
/// por segundo. Las que llegan antes esperan su turno en vez de fallar, y el
/// reloj y la espera son inyectables para probarlo sin esperar de verdad.
class LimitadorDeFrecuencia {
  LimitadorDeFrecuencia({
    this.intervalo = const Duration(seconds: 1),
    DateTime Function()? ahora,
    Future<void> Function(Duration)? dormir,
  }) : _ahora = ahora ?? DateTime.now,
       _dormir = dormir ?? Future<void>.delayed;

  final Duration intervalo;
  final DateTime Function() _ahora;
  final Future<void> Function(Duration) _dormir;

  Future<void> _cola = Future<void>.value();
  DateTime? _ultima;

  /// Corre [tarea] cuando le toca: al menos [intervalo] después de que empezó
  /// la anterior. Un fallo de una tarea no traba a las siguientes.
  Future<T> ejecutar<T>(Future<T> Function() tarea) {
    final resultado = Completer<T>();
    _cola = _cola.then((_) async {
      final ultima = _ultima;
      if (ultima != null) {
        final falta = intervalo - _ahora().difference(ultima);
        if (falta > Duration.zero) await _dormir(falta);
      }
      _ultima = _ahora();
      try {
        resultado.complete(await tarea());
      } catch (e, s) {
        resultado.completeError(e, s);
      }
    });
    return resultado.future;
  }
}
