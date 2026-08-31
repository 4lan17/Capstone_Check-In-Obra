import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/network/errores.dart';
import '../../core/theme/app_colors.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/herramienta.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import '../auth/sesion_controller.dart';
import 'bodega_providers.dart';
import 'pantalla_herramientas.dart';

/// Cierre del turno de bodega.
///
/// No es un botón: es una revisión. El turno se cierra igual aunque queden
/// herramientas fuera —en obra pasa, y bloquearlo obligaría a mentir— pero
/// cada una queda registrada como alerta de cierre de turno, para que el
/// turno siguiente sepa qué heredó.
class PantallaCierreTurno extends ConsumerStatefulWidget {
  const PantallaCierreTurno({super.key});

  @override
  ConsumerState<PantallaCierreTurno> createState() =>
      _PantallaCierreTurnoState();
}

class _PantallaCierreTurnoState extends ConsumerState<PantallaCierreTurno> {
  bool _enviando = false;
  String? _error;

  Future<void> _cerrar(int fuera) async {
    final obra = ref.read(obraEnCursoProvider);
    final sesion = ref.read(sesionProvider).valueOrNull;
    if (obra == null || sesion == null) return;

    setState(() {
      _enviando = true;
      _error = null;
    });

    try {
      final mensaje = fuera == 0
          ? 'Turno cerrado por ${sesion.nombre} sin herramientas pendientes.'
          : 'Turno cerrado por ${sesion.nombre} con $fuera '
                '${fuera == 1 ? 'herramienta' : 'herramientas'} fuera de bodega.';

      await ref
          .read(alertasApiProvider)
          .cerrarTurno(obraId: obra.id, mensaje: mensaje);

      recargarBodega(ref);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Turno cerrado y registrado')),
      );
    } catch (e) {
      setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sesion = ref.watch(sesionProvider).valueOrNull;
    final obra = ref.watch(obraEnCursoProvider);
    final hoy = ref.watch(movimientosDeHoyProvider).valueOrNull ?? const [];
    final abiertos = ref.watch(prestamosAbiertosProvider);
    final fuera = abiertos.valueOrNull?.length ?? 0;

    int cuenta(String tipo) => hoy.where((m) => m.tipo == tipo).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Cerrar turno')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    Formato.hora(DateTime.now()),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${sesion?.nombre ?? ''} · ${obra?.nombre ?? ''}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Panel(
              child: Row(
                children: [
                  Expanded(
                    child: Contador(
                      valor: '${cuenta('RECEPCION')}',
                      rotulo: 'Recepciones',
                    ),
                  ),
                  Expanded(
                    child: Contador(
                      valor: '${cuenta('DESPACHO')}',
                      rotulo: 'Despachos',
                    ),
                  ),
                  Expanded(
                    child: Contador(
                      valor: '${cuenta('CONSUMO')}',
                      rotulo: 'Consumos',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Contenido<List<Prestamo>>(
              valor: abiertos,
              alReintentar: () => ref.invalidate(prestamosProvider),
              estaVacio: (l) => l.isEmpty,
              vacio: const Panel(
                color: AppColors.successTint,
                borderColor: AppColors.success,
                child: Row(
                  children: [
                    ExcludeSemantics(
                      child: Icon(
                        Icons.check_circle_outline,
                        size: 20,
                        color: AppColors.successDark,
                      ),
                    ),
                    SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        'Todas las herramientas volvieron a bodega.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.successDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              constructor: (lista) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Panel(
                    color: AppColors.warningTint,
                    borderColor: AppColors.warning,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${lista.length} '
                          '${lista.length == 1 ? 'herramienta sigue fuera' : 'herramientas siguen fuera'}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.warningDark,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Recíbelas ahora si volvieron. Si cierras igual, cada '
                          'una queda anotada en la alerta de cierre de turno.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final p in lista) ...[
                    FilaPrestamo(prestamo: p),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              MensajeError(mensaje: _error!),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _enviando ? null : () => _cerrar(fuera),
              child: _enviando
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Cerrando…'),
                      ],
                    )
                  : Text(
                      fuera == 0
                          ? 'Cerrar turno'
                          : 'Cerrar turno con $fuera pendiente${fuera == 1 ? '' : 's'}',
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
