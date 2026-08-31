import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';

/// Campo de formulario del sistema. Los bordes y el relleno los pone el
/// `inputDecorationTheme`, así que acá solo va lo propio de cada campo.
class CampoTexto extends StatelessWidget {
  const CampoTexto({
    super.key,
    required this.controlador,
    required this.hint,
    required this.icono,
    this.teclado,
    this.oculto = false,
    this.mono = false,
    this.maxLength,
    this.formatters,
    this.sufijo,
    this.validador,
    this.alEnviar,
    this.habilitado = true,
  });

  final TextEditingController controlador;
  final String hint;
  final IconData icono;
  final TextInputType? teclado;
  final bool oculto;

  /// Monoespaciada para datos duros: códigos, SKU, cantidades, correos.
  final bool mono;

  final int? maxLength;
  final List<TextInputFormatter>? formatters;
  final Widget? sufijo;
  final String? Function(String?)? validador;
  final void Function(String)? alEnviar;
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controlador,
      keyboardType: teclado,
      obscureText: oculto,
      maxLength: maxLength,
      inputFormatters: formatters,
      validator: validador,
      onFieldSubmitted: alEnviar,
      enabled: habilitado,
      autocorrect: false,
      enableSuggestions: false,
      style: TextStyle(
        fontFamily: mono ? AppTheme.monoFamily : null,
        fontSize: 15,
        color: AppColors.primary,
      ),
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        prefixIcon: Icon(icono, size: 20, color: AppColors.secondary),
        suffixIcon: sufijo,
      ),
    );
  }
}

/// Rótulo + campo, que es como aparecen siempre en las pantallas.
class CampoConEtiqueta extends StatelessWidget {
  const CampoConEtiqueta({
    super.key,
    required this.etiqueta,
    required this.campo,
    this.ayuda,
  });

  final String etiqueta;
  final Widget campo;
  final String? ayuda;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          etiqueta.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 7),
        campo,
        if (ayuda != null) ...[
          const SizedBox(height: 6),
          Text(
            ayuda!,
            style: const TextStyle(
              fontSize: 12,
              height: 1.35,
              color: AppColors.secondary,
            ),
          ),
        ],
      ],
    );
  }
}
