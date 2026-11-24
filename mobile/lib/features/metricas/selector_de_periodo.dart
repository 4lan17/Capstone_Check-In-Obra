import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/modelos/metricas.dart';

/// Los tres periodos en una fila: 7 días · 30 días · Toda la obra. El elegido
/// va relleno; el resto, en blanco.
class SelectorDePeriodo extends StatelessWidget {
  const SelectorDePeriodo({
    super.key,
    required this.periodo,
    required this.alCambiar,
  });

  final PeriodoMetricas periodo;
  final ValueChanged<PeriodoMetricas> alCambiar;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          for (final p in PeriodoMetricas.values)
            Expanded(
              child: _Segmento(
                etiqueta: p.etiqueta,
                elegido: p == periodo,
                alTocar: () => alCambiar(p),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segmento extends StatelessWidget {
  const _Segmento({
    required this.etiqueta,
    required this.elegido,
    required this.alTocar,
  });

  final String etiqueta;
  final bool elegido;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: elegido,
      label: etiqueta,
      onTap: alTocar,
      excludeSemantics: true,
      child: Material(
        color: elegido ? AppColors.primary : AppColors.card,
        child: InkWell(
          onTap: alTocar,
          child: Container(
            // 48 px: el mínimo cómodo para un dedo con guantes.
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              etiqueta,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: elegido ? FontWeight.w600 : FontWeight.w500,
                color: elegido ? Colors.white : AppColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
