import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/modelos/desviacion.dart';
import '../../data/modelos/presupuesto.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import 'presupuesto_providers.dart';

/// Cuánto se gastó de más (o de menos) respecto del presupuesto (D8) y qué
/// merma tuvo cada material contra la que se estimó al cubicar (D9).
///
/// Lo que se pasa del umbral se destaca con color, ícono **y** texto: el color
/// solo no lo ve quien no distingue rojos, ni lo anuncia un lector de pantalla.
class PantallaDesviacion extends ConsumerWidget {
  const PantallaDesviacion({super.key, required this.presupuesto});

  final Presupuesto presupuesto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desviacion = ref.watch(desviacionProvider(presupuesto.id));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Desviación')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(desviacionProvider(presupuesto.id).future),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Contenido<Desviacion>(
              valor: desviacion,
              alReintentar: () =>
                  ref.invalidate(desviacionProvider(presupuesto.id)),
              constructor: (d) =>
                  _Cuerpo(desviacion: d, presupuesto: presupuesto),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cuerpo extends StatelessWidget {
  const _Cuerpo({required this.desviacion, required this.presupuesto});

  final Desviacion desviacion;
  final Presupuesto presupuesto;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Resumen(desviacion: desviacion, obra: presupuesto.obraNombre),
        const SizedBox(height: 18),
        const Etiqueta('Por material'),
        const SizedBox(height: 10),
        if (desviacion.materiales.isEmpty)
          const Vacio(
            icono: Icons.inventory_2_outlined,
            titulo: 'Aún no hay consumo en bodega',
            detalle:
                'Cuando bodega despache o consuma material de esta obra, aquí '
                'verás cuánto se gastó contra lo presupuestado.',
          )
        else
          for (final m in desviacion.materiales) ...[
            _FilaMaterial(
              material: m,
              key: ValueKey('material-${m.materialId}'),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

/// La cifra grande: cuánto se desvió el gasto en total.
class _Resumen extends StatelessWidget {
  const _Resumen({required this.desviacion, required this.obra});

  final Desviacion desviacion;
  final String obra;

  @override
  Widget build(BuildContext context) {
    final d = desviacion;
    final pct = d.desviacionPct;
    final color = d.superaUmbral
        ? AppColors.destructiveDark
        : AppColors.primary;

    return Panel(
      color: d.superaUmbral ? AppColors.destructiveTint : AppColors.card,
      borderColor: d.superaUmbral ? AppColors.destructive : AppColors.border,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Desviación · $obra', style: AppTexto.subtitulo),
          const SizedBox(height: 12),
          Text(
            pct == null ? 'Sin presupuesto' : Formato.porcentajeConSigno(pct),
            style: AppTexto.cifra.copyWith(color: color),
          ),
          Text(
            Formato.pesosConSigno(d.desviacionMonto),
            style: AppTexto.dato.copyWith(color: color),
          ),
          const SizedBox(height: 10),
          _EtiquetaUmbral(superaUmbral: d.superaUmbral, umbral: d.umbralPct),
          const SizedBox(height: 14),
          _Cifra(
            rotulo: 'Presupuestado',
            valor: Formato.pesos(d.presupuestado),
          ),
          const SizedBox(height: 6),
          _Cifra(rotulo: 'Ejecutado', valor: Formato.pesos(d.ejecutado)),
          if (d.mermaRealVsEstimada != null) ...[
            const SizedBox(height: 12),
            Text(
              'Merma real ${_puntos(d.mermaRealVsEstimada!)} respecto de la '
              'estimada al cubicar.',
              style: AppTexto.cuerpoChico.copyWith(color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// "+2,1 puntos", "−1 punto": la merma se compara en puntos porcentuales.
String _puntos(double v) {
  final texto = Formato.cantidadConSigno(v);
  return '$texto ${v.abs() == 1 ? 'punto' : 'puntos'}';
}

class _Cifra extends StatelessWidget {
  const _Cifra({required this.rotulo, required this.valor});

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            rotulo,
            style: AppTexto.cuerpoChico.copyWith(color: AppColors.textMuted),
          ),
        ),
        Text(valor, style: AppTexto.dato),
      ],
    );
  }
}

/// Dice si se superó el umbral con ícono y texto, no solo con color.
class _EtiquetaUmbral extends StatelessWidget {
  const _EtiquetaUmbral({required this.superaUmbral, required this.umbral});

  final bool superaUmbral;
  final double? umbral;

  @override
  Widget build(BuildContext context) {
    final de = umbral == null ? '' : ' de ${Formato.porcentaje(umbral!)}';
    return _Aviso(
      icono: superaUmbral
          ? Icons.warning_amber_rounded
          : Icons.check_circle_outline,
      texto: superaUmbral ? 'Supera el umbral$de' : 'Dentro del umbral$de',
      color: superaUmbral ? AppColors.destructiveDark : AppColors.successDark,
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icono, required this.texto, required this.color});

  final IconData icono;
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // El texto ya dice lo mismo: el ícono es refuerzo visual.
        ExcludeSemantics(child: Icon(icono, size: 18, color: color)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            texto,
            style: AppTexto.cuerpoChico.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _FilaMaterial extends StatelessWidget {
  const _FilaMaterial({super.key, required this.material});

  final DesviacionMaterial material;

  @override
  Widget build(BuildContext context) {
    final m = material;
    final pasada = m.superaUmbral;
    final alerta = pasada || m.consumidoSinPresupuestar;
    final color = pasada ? AppColors.destructiveDark : AppColors.primary;
    final pct = m.desviacionPct;
    final porcentaje = pct == null
        ? 'sin presupuesto'
        : Formato.porcentajeConSigno(pct);
    final monto = Formato.pesosConSigno(m.desviacionMonto);

    return Semantics(
      // Cada material es un ítem propio de la lista: sin `container`, el
      // lector de pantalla los leería fundidos en uno solo.
      container: true,
      label: _etiqueta(m, porcentaje, monto),
      excludeSemantics: true,
      child: Panel(
        color: pasada
            ? AppColors.destructiveTint
            : alerta
            ? AppColors.warningTint
            : AppColors.card,
        borderColor: pasada
            ? AppColors.destructive
            : alerta
            ? AppColors.warning
            : AppColors.border,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.nombre, style: AppTexto.subtitulo),
                      const SizedBox(height: 2),
                      Text(
                        m.sku,
                        style: AppTexto.cuerpoChico.copyWith(
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      porcentaje,
                      style: AppTexto.dato.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      monto,
                      style: AppTexto.cuerpoChico.copyWith(color: color),
                    ),
                  ],
                ),
              ],
            ),
            if (pasada) ...[
              const SizedBox(height: 8),
              const _Aviso(
                icono: Icons.warning_amber_rounded,
                texto: 'Supera el umbral',
                color: AppColors.destructiveDark,
              ),
            ] else if (m.consumidoSinPresupuestar) ...[
              const SizedBox(height: 8),
              const _Aviso(
                icono: Icons.report_problem_outlined,
                texto: 'Consumido sin presupuestar',
                color: AppColors.warningInk,
              ),
            ],
            const SizedBox(height: 10),
            _Cifra(
              rotulo:
                  'Presupuestado · ${_cantidad(m.cantidadPresupuestada, m)}',
              valor: Formato.pesos(m.montoPresupuestado),
            ),
            const SizedBox(height: 4),
            _Cifra(
              rotulo: 'Ejecutado · ${_cantidad(m.cantidadEjecutada, m)}',
              valor: Formato.pesos(m.montoEjecutado),
            ),
            const SizedBox(height: 10),
            _Merma(material: m),
          ],
        ),
      ),
    );
  }
}

String _cantidad(double v, DesviacionMaterial m) {
  final unidad = m.unidad;
  final texto = Formato.cantidad(v);
  return unidad == null || unidad.isEmpty ? texto : '$texto $unidad';
}

String _etiqueta(DesviacionMaterial m, String porcentaje, String monto) {
  final partes = [
    m.nombre,
    'desviación $porcentaje, $monto',
    if (m.superaUmbral) 'supera el umbral',
    if (m.consumidoSinPresupuestar) 'consumido sin presupuestar',
    'presupuestado ${Formato.pesos(m.montoPresupuestado)}, '
        'ejecutado ${Formato.pesos(m.montoEjecutado)}',
    _mermaTexto(m),
  ];
  return partes.join('. ');
}

String _mermaTexto(DesviacionMaterial m) {
  final estimada = m.mermaEstimadaPct == null
      ? 'sin parámetro'
      : Formato.porcentaje(m.mermaEstimadaPct!);
  final real = m.mermaRealPct == null
      ? 'sin cubicación'
      : Formato.porcentaje(m.mermaRealPct!);
  return 'Merma estimada $estimada, real: $real';
}

/// La merma estimada con que se cubicó contra la que realmente se perdió.
class _Merma extends StatelessWidget {
  const _Merma({required this.material});

  final DesviacionMaterial material;

  @override
  Widget build(BuildContext context) {
    final m = material;
    final estimada = m.mermaEstimadaPct;
    final real = m.mermaRealPct;
    final exceso = (estimada != null && real != null) ? real - estimada : null;
    final sobra = exceso != null && exceso > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          estimada == null
              ? 'Merma estimada: sin parámetro'
              : 'Merma estimada ${Formato.porcentaje(estimada)}',
          style: AppTexto.cuerpoChico.copyWith(color: AppColors.textMuted),
        ),
        Text(
          real == null
              ? 'Merma real: sin cubicación'
              : 'Merma real ${Formato.porcentaje(real)}',
          style: AppTexto.cuerpoChico.copyWith(color: AppColors.textMuted),
        ),
        if (sobra) ...[
          const SizedBox(height: 4),
          _Aviso(
            icono: Icons.trending_up,
            texto:
                '${Formato.cantidad(exceso)} '
                '${exceso == 1 ? 'punto' : 'puntos'} más que la estimada',
            color: AppColors.warningInk,
          ),
        ],
      ],
    );
  }
}
