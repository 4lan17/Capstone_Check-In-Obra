import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/errores.dart';
import '../../core/storage/sesion_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../shared_widgets/panel.dart';
import 'pantalla_acceso_pin.dart';
import 'sesion_controller.dart';

/// Acceso por correo + PIN. Es la vía de admin y jefe de terreno; el
/// trabajador entra por el acceso rápido de abajo, que solo pide el PIN.
///
/// Nota sobre el diseño: el mockup rotula este campo como "Contraseña", pero
/// `Usuario` no tiene contraseña — solo `pinHash`. Se rotula "PIN" para que
/// coincida con lo que el backend realmente valida.
class PantallaAcceso extends ConsumerStatefulWidget {
  const PantallaAcceso({super.key});

  @override
  ConsumerState<PantallaAcceso> createState() => _PantallaAccesoState();
}

class _PantallaAccesoState extends ConsumerState<PantallaAcceso> {
  final _email = TextEditingController();
  final _pin = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _ocultarPin = true;

  @override
  void dispose() {
    _email.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    await ref
        .read(sesionProvider.notifier)
        .entrarConCorreo(email: _email.text, pin: _pin.text);
  }

  @override
  Widget build(BuildContext context) {
    final sesion = ref.watch(sesionProvider);
    final recordado = ref.watch(usuarioRecordadoProvider).valueOrNull;
    final cargando = sesion.isLoading;

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Column(
        children: [
          const _Encabezado(),
          Expanded(
            child: Container(
              width: double.infinity,
              color: Colors.white,
              // `bottom` sí: el último elemento del formulario quedaba bajo la
              // barra de gestos en los teléfonos sin botones físicos.
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Etiqueta('Correo de empresa'),
                        const SizedBox(height: 7),
                        _CampoTexto(
                          controlador: _email,
                          hint: 'nombre@empresa.cl',
                          icono: Icons.mail_outline,
                          teclado: TextInputType.emailAddress,
                          mono: true,
                          validador: (v) => (v == null || !v.contains('@'))
                              ? 'Escribe un correo válido'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        const Etiqueta('PIN de 4 dígitos'),
                        const SizedBox(height: 7),
                        _CampoTexto(
                          controlador: _pin,
                          hint: '••••',
                          icono: Icons.lock_outline,
                          teclado: TextInputType.number,
                          oculto: _ocultarPin,
                          mono: true,
                          maxLength: 4,
                          formatters: [FilteringTextInputFormatter.digitsOnly],
                          // Un botón que es solo un ícono no se anuncia solo:
                          // sin `tooltip`, el lector de pantalla lo lee como
                          // "botón" a secas. El texto además cambia con el
                          // estado, para que se sepa qué va a pasar al tocarlo.
                          sufijo: IconButton(
                            tooltip: _ocultarPin
                                ? 'Mostrar el PIN'
                                : 'Ocultar el PIN',
                            icon: Icon(
                              _ocultarPin
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 20,
                              color: AppColors.secondary,
                            ),
                            onPressed: () =>
                                setState(() => _ocultarPin = !_ocultarPin),
                          ),
                          validador: (v) => (v == null || v.length != 4)
                              ? 'El PIN son 4 dígitos'
                              : null,
                          alEnviar: (_) => _entrar(),
                        ),
                        if (sesion.hasError) ...[
                          const SizedBox(height: 14),
                          _Error(mensaje: mensajeDeError(sesion.error!)),
                        ],
                        const SizedBox(height: 18),
                        // Mientras carga se mantiene el texto junto al giro. Un
                        // botón que se queda solo con un spinner pierde su
                        // nombre: el lector de pantalla deja de tener qué
                        // anunciar y quien mira ya no sabe qué se está haciendo.
                        FilledButton(
                          onPressed: cargando ? null : _entrar,
                          child: cargando
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
                                    Text('Entrando…'),
                                  ],
                                )
                              : const Text('Entrar'),
                        ),
                        if (recordado != null) ...[
                          const SizedBox(height: 20),
                          const _Separador('O en este teléfono'),
                          const SizedBox(height: 16),
                          _AccesoRapido(recordado: recordado),
                        ],
                        const SizedBox(height: 22),
                        const _NotaPin(),
                        const SizedBox(height: 16),
                        const Text(
                          'Check-In-Obra · v1.0 MVP 1',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: AppTheme.monoFamily,
                            fontSize: 11,
                            color: AppColors.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  const _Encabezado();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Center se estira al ancho disponible, asi que centra el logo
            // sin alterar el crossAxisAlignment.start que alinea el resto.
            Center(
              child: Image.asset(
                'assets/images/logo.png',
                height: 96,
                // El PNG ya trae el nombre bajo el isotipo, asi que no lleva
                // Text al lado. El semanticLabel cubre a los lectores de
                // pantalla, que antes leian el texto.
                semanticLabel: 'Check-In Obra',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Una sola cuenta para los cuatro roles. Lo que puedes hacer '
              'adentro lo decide tu rol, no una app distinta.',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppColors.textOnDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CampoTexto extends StatelessWidget {
  const _CampoTexto({
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
  });

  final TextEditingController controlador;
  final String hint;
  final IconData icono;
  final TextInputType? teclado;
  final bool oculto;
  final bool mono;
  final int? maxLength;
  final List<TextInputFormatter>? formatters;
  final Widget? sufijo;
  final String? Function(String?)? validador;
  final void Function(String)? alEnviar;

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
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppColors.borderControl),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppColors.borderControl),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppColors.accent, width: 2),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppColors.destructive),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: AppColors.destructive, width: 2),
        ),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    // `liveRegion` hace que el lector de pantalla lea el mensaje en cuanto
    // aparece. Sin esto el error se dibuja en silencio: quien no lo ve se
    // queda esperando a que el botón haga algo.
    return Semantics(
      liveRegion: true,
      child: Panel(
        color: AppColors.destructiveTint,
        borderColor: AppColors.destructive,
        padding: const EdgeInsets.all(13),
        child: Row(
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
      ),
    );
  }
}

class _Separador extends StatelessWidget {
  const _Separador(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.border, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Etiqueta(texto, color: AppColors.secondary),
        ),
        const Expanded(child: Divider(color: AppColors.border, height: 1)),
      ],
    );
  }
}

class _AccesoRapido extends StatelessWidget {
  const _AccesoRapido({required this.recordado});

  final UsuarioRecordado recordado;

  @override
  Widget build(BuildContext context) {
    return PanelTocable(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const PantallaAccesoPin())),
      // El panel entero es un solo control. Sin una etiqueta que lo diga, el
      // lector de pantalla recita nombre, rol y "PIN de 4 dígitos" como tres
      // textos sueltos y nunca menciona que ahí se toca para entrar.
      semanticLabel:
          'Entrar como ${recordado.nombre}, '
          '${nombreDeRol(recordado.rol)}, con PIN de 4 dígitos',
      color: AppColors.background,
      child: Row(
        children: [
          Iniciales(recordado.nombre),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recordado.nombre,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${nombreDeRol(recordado.rol).toUpperCase()} · PIN DE 4 DÍGITOS',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            size: 22,
            color: AppColors.accentFill,
          ),
        ],
      ),
    );
  }
}

class _NotaPin extends StatelessWidget {
  const _NotaPin();

  @override
  Widget build(BuildContext context) {
    return Panel(
      color: AppColors.background,
      padding: const EdgeInsets.all(13),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(
              Icons.info_outline,
              size: 19,
              color: AppColors.secondary,
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'El correo es para administradores y jefes de terreno. En obra se '
              'entra con PIN: el teléfono recuerda al usuario y el PIN nunca '
              'sale del equipo.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
