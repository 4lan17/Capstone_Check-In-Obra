import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/modelos/metricas.dart';
import '../../shared_widgets/estados.dart';
import 'selector_de_periodo.dart';

/// El esqueleto de las tres pantallas de métricas: encabezado con el nombre de
/// lo que se mide, el selector de periodo y las tarjetas que cada rol arma con
/// sus datos. Se ocupa también de cargar, del error con «Reintentar» y de
/// refrescar tirando hacia abajo.
class PantallaMetricas<T> extends ConsumerStatefulWidget {
  const PantallaMetricas({
    super.key,
    required this.subtitulo,
    required this.observar,
    required this.invalidar,
    required this.tarjetas,
  });

  /// La obra o la empresa que se mide, bajo el título.
  final String subtitulo;

  /// Lee las métricas del periodo (con `ref.watch`).
  final AsyncValue<T> Function(WidgetRef ref, PeriodoMetricas periodo) observar;

  /// Descarta lo leído para volver a pedirlo.
  final void Function(WidgetRef ref, PeriodoMetricas periodo) invalidar;

  /// Las tarjetas, con los datos ya cargados.
  final List<Widget> Function(
    BuildContext context,
    WidgetRef ref,
    T datos,
    PeriodoMetricas periodo,
  )
  tarjetas;

  @override
  ConsumerState<PantallaMetricas<T>> createState() =>
      _PantallaMetricasState<T>();
}

class _PantallaMetricasState<T> extends ConsumerState<PantallaMetricas<T>> {
  PeriodoMetricas _periodo = PeriodoMetricas.treintaDias;

  @override
  Widget build(BuildContext context) {
    final metricas = widget.observar(ref, _periodo);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Métricas'),
            Text(
              widget.subtitulo,
              style: const TextStyle(
                fontFamily: AppTheme.monoFamily,
                fontSize: 11.5,
                fontWeight: FontWeight.w400,
                color: AppColors.secondary,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () async {
            widget.invalidar(ref, _periodo);
            await Future<void>.delayed(const Duration(milliseconds: 300));
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              SelectorDePeriodo(
                periodo: _periodo,
                alCambiar: (p) => setState(() => _periodo = p),
              ),
              const SizedBox(height: 10),
              Contenido<T>(
                valor: metricas,
                alReintentar: () => widget.invalidar(ref, _periodo),
                constructor: (datos) => Column(
                  children: [
                    for (final t in widget.tarjetas(
                      context,
                      ref,
                      datos,
                      _periodo,
                    )) ...[t, const SizedBox(height: 10)],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
