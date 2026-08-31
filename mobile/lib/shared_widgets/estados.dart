import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/errores.dart';
import '../core/theme/app_colors.dart';
import 'panel.dart';

/// Dibuja un `AsyncValue` con los tres estados resueltos de una vez.
///
/// El caso vacío es un parámetro y no un olvido: una lista sin elementos en
/// obra casi nunca significa "no hay nada", significa "todavía no cargaste el
/// catálogo" o "el turno recién empieza", y decir cuál de las dos ahorra una
/// llamada al jefe de terreno.
class Contenido<T> extends StatelessWidget {
  const Contenido({
    super.key,
    required this.valor,
    required this.constructor,
    required this.alReintentar,
    this.vacio,
    this.estaVacio,
  });

  final AsyncValue<T> valor;
  final Widget Function(T dato) constructor;
  final VoidCallback alReintentar;

  /// Qué mostrar cuando el dato llegó pero no tiene nada dentro.
  final Widget? vacio;
  final bool Function(T dato)? estaVacio;

  @override
  Widget build(BuildContext context) {
    return switch (valor) {
      AsyncError(:final error) => MensajeError(
        mensaje: mensajeDeError(error),
        alReintentar: alReintentar,
      ),
      AsyncData(:final value) =>
        (estaVacio?.call(value) ?? false) && vacio != null
            ? vacio!
            : constructor(value),
      _ => const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.accentFill),
        ),
      ),
    };
  }
}

class MensajeError extends StatelessWidget {
  const MensajeError({super.key, required this.mensaje, this.alReintentar});

  final String mensaje;
  final VoidCallback? alReintentar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Panel(
        color: AppColors.destructiveTint,
        borderColor: AppColors.destructive,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ExcludeSemantics(
                  child: Icon(
                    Icons.error_outline,
                    size: 20,
                    color: AppColors.destructiveDark,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    mensaje,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: AppColors.destructiveDark,
                    ),
                  ),
                ),
              ],
            ),
            if (alReintentar != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: alReintentar,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reintentar'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.destructiveDark,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Estado vacío con una salida: decir que no hay nada sin decir qué hacer
/// deja a quien está en obra sin siguiente paso.
class Vacio extends StatelessWidget {
  const Vacio({
    super.key,
    required this.icono,
    required this.titulo,
    required this.detalle,
    this.accion,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 8),
      child: Column(
        children: [
          ExcludeSemantics(
            child: Icon(icono, size: 40, color: AppColors.textFaint),
          ),
          const SizedBox(height: 14),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            detalle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.secondary,
            ),
          ),
          if (accion != null) ...[const SizedBox(height: 18), accion!],
        ],
      ),
    );
  }
}

/// Cifra grande con su rótulo debajo — los contadores del inicio de bodega.
///
/// Se centra en su columna: siempre va dentro de un `Expanded` en una fila de
/// tres, y alineado a la izquierda la cifra queda descolgada del rótulo cuando
/// los rótulos tienen anchos distintos ("Movimientos del turno" contra
/// "Alertas sin resolver").
class Contador extends StatelessWidget {
  const Contador({
    super.key,
    required this.valor,
    required this.rotulo,
    this.color = AppColors.primary,
  });

  final String valor;
  final String rotulo;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$valor $rotulo',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            valor,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              height: 1.1,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            rotulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.25,
              color: AppColors.secondary,
            ),
          ),
        ],
      ),
    );
  }
}
