import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_forma.dart';
import '../../core/theme/app_theme.dart';

/// Lo que se ve en lugar de un gráfico sin datos.
///
/// Un gráfico vacío —ejes sin línea— no dice nada: se prefiere una frase que
/// diga por qué no hay nada. Reserva el alto del gráfico para que la tarjeta
/// no cambie de tamaño al llegar los datos.
class GraficoVacio extends StatelessWidget {
  const GraficoVacio({super.key, required this.mensaje, this.alto = 112});

  final String mensaje;
  final double alto;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: mensaje,
      excludeSemantics: true,
      child: Container(
        constraints: BoxConstraints(minHeight: alto),
        width: double.infinity,
        padding: const EdgeInsets.all(AppEspacio.md),
        decoration: const BoxDecoration(
          color: AppColors.sunken,
          borderRadius: AppForma.borde,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.insert_chart_outlined,
              size: 26,
              color: AppColors.secondary,
            ),
            const SizedBox(height: AppEspacio.sm),
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: AppTexto.cuerpoChico.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
