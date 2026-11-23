import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/errores.dart';
import '../../core/reloj.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/codigo_credencial.dart';

/// Lo que se dice cuando no hay red: en vez de un QR que no sirve.
const mensajeCredencialSinRed =
    'Sin conexión: no se puede mostrar la credencial';

/// Cada cuántos segundos se pide un código nuevo mientras se muestra. La
/// vigencia es de 120: renovar a los 60 deja siempre al menos un minuto de
/// margen para llegar al mesón con el código a la vista.
const segundosEntreRenovaciones = 60;

/// Cada cuántos segundos se reintenta mientras no hay código.
const segundosEntreReintentos = 10;

/// Qué muestra la credencial en este momento.
sealed class EstadoCodigo {
  const EstadoCodigo();
}

/// Todavía no hay código (la pestaña no está activa, o se está pidiendo).
class CodigoCargando extends EstadoCodigo {
  const CodigoCargando();
}

/// Un código vigente, con los segundos que le quedan.
class CodigoVigente extends EstadoCodigo {
  const CodigoVigente({required this.codigo, required this.restante});

  final CodigoCredencial codigo;
  final int restante;

  /// De 1 (recién emitido) a 0 (vencido), para el indicador.
  double get proporcion => codigo.vigenciaSegundos == 0
      ? 0
      : (restante / codigo.vigenciaSegundos).clamp(0.0, 1.0);

  /// `1:30`.
  String get restanteTexto =>
      '${restante ~/ 60}:${(restante % 60).toString().padLeft(2, '0')}';
}

/// No se pudo tener un código vigente. Nunca se muestra uno vencido.
class CodigoNoDisponible extends EstadoCodigo {
  const CodigoNoDisponible({required this.mensaje, required this.sinConexion});

  final String mensaje;
  final bool sinConexion;
}

/// Mantiene el código de la credencial del trabajador: lo pide al abrir la
/// pestaña, lo renueva solo y lo descarta apenas vence.
///
/// Dos decisiones de seguridad:
///
/// * **Nunca se guarda.** Ni en disco ni de una apertura a la siguiente: al
///   salir de la pestaña se olvida, y al volver se pide uno recién emitido.
///   Un código guardado es exactamente el UUID fijo que se quiso eliminar.
/// * **El tiempo se cuenta con el reloj del teléfono desde que el código
///   llegó**, no con la hora del servidor: un teléfono con la hora mal puesta
///   no debe dar por vencido un código bueno, y al volver del segundo plano el
///   reloj sigue corriendo aunque los temporizadores no hayan corrido.
class CodigoCredencialNotifier extends Notifier<EstadoCodigo> {
  Timer? _temporizador;
  bool _activo = false;
  bool _pidiendo = false;

  /// Cambia cada vez que la pestaña se activa o se desactiva: una respuesta
  /// que llega de una activación anterior no vale.
  int _generacion = 0;
  bool _fallo = false;

  CodigoCredencial? _vigente;
  DateTime? _recibidoEl;
  DateTime? _ultimoIntento;

  @override
  EstadoCodigo build() {
    ref.onDispose(_detener);
    return const CodigoCargando();
  }

  DateTime get _ahora => ref.read(relojProvider)();

  /// La pestaña de la credencial pasó a verse: se pide un código nuevo y se
  /// empieza a contar.
  void activar() {
    if (_activo) return;
    _activo = true;
    _vigente = null;
    state = const CodigoCargando();
    _temporizador = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _latido(),
    );
    unawaited(_pedir());
  }

  /// La pestaña dejó de verse: se olvida el código y se paran los pedidos.
  void desactivar() {
    if (!_activo) return;
    _detener();
    state = const CodigoCargando();
  }

  /// El botón «Reintentar».
  Future<void> reintentar() => _pedir(mostrarCargando: true);

  /// Tras revocar los códigos vigentes: el de la pantalla ya no sirve.
  Future<void> renovarAhora() {
    _vigente = null;
    return _pedir(mostrarCargando: true);
  }

  /// La app volvió del segundo plano: lo que cuente el reloj manda, no los
  /// temporizadores que pudieron no correr.
  void alReanudar() {
    if (_activo) _latido();
  }

  void _detener() {
    _temporizador?.cancel();
    _temporizador = null;
    _activo = false;
    _pidiendo = false;
    _fallo = false;
    _generacion++;
    _vigente = null;
    _recibidoEl = null;
    _ultimoIntento = null;
  }

  Future<void> _pedir({bool mostrarCargando = false}) async {
    if (!_activo || _pidiendo) return;
    final generacion = _generacion;
    _pidiendo = true;
    _ultimoIntento = _ahora;
    if (mostrarCargando && _vigente == null) state = const CodigoCargando();
    try {
      final nuevo = await ref
          .read(trabajadoresApiProvider)
          .pedirCodigoCredencial();
      if (generacion != _generacion) return;
      _fallo = false;
      _vigente = nuevo;
      _recibidoEl = _ahora;
      state = CodigoVigente(codigo: nuevo, restante: nuevo.vigenciaSegundos);
    } catch (e) {
      if (generacion != _generacion) return;
      _fallo = true;
      // Un código todavía vigente sigue sirviendo en bodega: una renovación
      // fallida no lo quita. Cuando venza, `_latido` lo descarta.
      if (_vigente != null && _restante > 0) return;
      _vigente = null;
      final sinRed = _esFaltaDeRed(e);
      state = CodigoNoDisponible(
        mensaje: sinRed ? mensajeCredencialSinRed : mensajeDeError(e),
        sinConexion: sinRed,
      );
    } finally {
      if (generacion == _generacion) _pidiendo = false;
    }
  }

  static bool _esFaltaDeRed(Object e) =>
      e is DioException &&
      const {
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      }.contains(e.type);

  int get _restante {
    final codigo = _vigente;
    final desde = _recibidoEl;
    if (codigo == null || desde == null) return 0;
    final pasaron = _ahora.difference(desde).inSeconds;
    return codigo.vigenciaSegundos - pasaron;
  }

  /// Una vez por segundo: actualiza el contador, renueva si toca y descarta lo
  /// vencido.
  void _latido() {
    if (!_activo) return;
    final codigo = _vigente;
    if (codigo == null) {
      // Sin código: se reintenta cada tanto, para cuando vuelva la señal.
      final ultimo = _ultimoIntento;
      final tocaReintentar =
          state is! CodigoNoDisponible ||
          ultimo == null ||
          _ahora.difference(ultimo).inSeconds >= segundosEntreReintentos;
      if (tocaReintentar) unawaited(_pedir());
      return;
    }

    final restante = _restante;
    if (restante <= 0) {
      // Venció: no queda a la vista ni un segundo más.
      _vigente = null;
      state = const CodigoCargando();
      unawaited(_pedir());
      return;
    }

    final transcurrido = codigo.vigenciaSegundos - restante;
    final cadaCuanto = codigo.vigenciaSegundos ~/ 2 < segundosEntreRenovaciones
        ? codigo.vigenciaSegundos ~/ 2
        : segundosEntreRenovaciones;
    // Si la última renovación falló, se insiste más seguido: el código actual
    // tiene los días contados.
    final espera = _fallo ? segundosEntreReintentos : cadaCuanto;
    final ultimo = _ultimoIntento;
    final hayPedidoReciente =
        ultimo != null && _ahora.difference(ultimo).inSeconds < espera;
    if (transcurrido >= cadaCuanto && !hayPedidoReciente) {
      unawaited(_pedir());
    }
    state = CodigoVigente(codigo: codigo, restante: restante);
  }
}

/// El código de la credencial del trabajador, en vivo.
final codigoCredencialProvider =
    NotifierProvider<CodigoCredencialNotifier, EstadoCodigo>(
      CodigoCredencialNotifier.new,
    );
