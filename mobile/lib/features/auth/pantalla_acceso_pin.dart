import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/errores.dart';
import '../../core/storage/sesion_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../shared_widgets/panel.dart';
import 'sesion_controller.dart';

/// Acceso rápido con PIN para el usuario que el teléfono ya recuerda.
///
/// El teclado es propio, no el del sistema: teclas grandes que se aciertan
/// con guantes, y así el PIN nunca pasa por el teclado predictivo de Android.
class PantallaAccesoPin extends ConsumerStatefulWidget {
  const PantallaAccesoPin({super.key});

  @override
  ConsumerState<PantallaAccesoPin> createState() => _PantallaAccesoPinState();
}

class _PantallaAccesoPinState extends ConsumerState<PantallaAccesoPin> {
  String _pin = '';

  Future<void> _tecla(String d, UsuarioRecordado usuario) async {
    if (_pin.length >= 4) return;
    setState(() => _pin += d);
    if (_pin.length == 4) {
      // Pequeña pausa para que se vea el cuarto punto antes de validar.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      await ref
          .read(sesionProvider.notifier)
          .entrarConPin(usuarioId: usuario.usuarioId, pin: _pin);
      // Si falló, se limpia para reintentar.
      if (mounted && ref.read(sesionProvider).hasError) {
        setState(() => _pin = '');
      }
    }
  }

  void _borrar() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final sesion = ref.watch(sesionProvider);
    final recordadoAsync = ref.watch(usuarioRecordadoProvider);

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: recordadoAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: Colors.white)),
        error: (e, _) => Center(
          child: Text(
            mensajeDeError(e),
            style: const TextStyle(color: Colors.white),
          ),
        ),
        data: (usuario) {
          if (usuario == null) {
            // Sin usuario recordado no hay a quién autenticar: se vuelve.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) Navigator.of(context).maybePop();
            });
            return const SizedBox.shrink();
          }
          return Column(
            children: [
              _Encabezado(usuario: usuario),
              Expanded(
                child: Container(
                  width: double.infinity,
                  color: Colors.white,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                    child: Column(
                      children: [
                        _Titulo(
                          error: sesion.hasError
                              ? mensajeDeError(sesion.error!)
                              : null,
                          cargando: sesion.isLoading,
                        ),
                        const SizedBox(height: 14),
                        _Puntos(cantidad: _pin.length, error: sesion.hasError),
                        const SizedBox(height: 22),
                        _Teclado(
                          habilitado: !sesion.isLoading,
                          alPulsar: (d) => _tecla(d, usuario),
                          alLimpiar: () => setState(() => _pin = ''),
                          alBorrar: _borrar,
                        ),
                        const SizedBox(height: 18),
                        const Panel(
                          color: AppColors.background,
                          padding: EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.lock_outline,
                                size: 19,
                                color: AppColors.secondary,
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'El PIN no se guarda en el teléfono. Si lo '
                                  'olvidaste, lo restablece el administrador '
                                  'de la empresa.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.4,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Encabezado extends ConsumerWidget {
  const _Encabezado({required this.usuario});

  final UsuarioRecordado usuario;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 16, 20),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const Expanded(
                  child: Text(
                    'Acceso con PIN',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Panel(
                color: const Color(0xFF1E293B),
                borderColor: const Color(0xFF475569),
                padding: const EdgeInsets.all(13),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      color: const Color(0xFF475569),
                      alignment: Alignment.center,
                      child: Text(
                        Iniciales.de(usuario.nombre),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            usuario.nombre,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            nombreDeRol(usuario.rol).toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                              color: AppColors.textFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await ref
                            .read(sesionProvider.notifier)
                            .cambiarDeUsuario();
                        if (context.mounted) Navigator.of(context).maybePop();
                      },
                      child: const Text(
                        'Cambiar',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFFFDBA74),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo({this.error, required this.cargando});

  final String? error;
  final bool cargando;

  @override
  Widget build(BuildContext context) {
    if (cargando) {
      return const Text(
        'Verificando…',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textMuted,
        ),
      );
    }
    return Text(
      error ?? 'Ingresa tu PIN de 4 dígitos',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: error != null ? AppColors.destructiveDark : AppColors.primary,
      ),
    );
  }
}

class _Puntos extends StatelessWidget {
  const _Puntos({required this.cantidad, required this.error});

  final int cantidad;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final lleno = i < cantidad;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 7),
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: lleno
                ? (error ? AppColors.destructive : AppColors.primary)
                : Colors.white,
            border: Border.all(
              color: error ? AppColors.destructive : const Color(0xFFCBD5E1),
              width: 2,
            ),
          ),
        );
      }),
    );
  }
}

class _Teclado extends StatelessWidget {
  const _Teclado({
    required this.habilitado,
    required this.alPulsar,
    required this.alLimpiar,
    required this.alBorrar,
  });

  final bool habilitado;
  final void Function(String) alPulsar;
  final VoidCallback alLimpiar;
  final VoidCallback alBorrar;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      // Teclas de ~62 px de alto: muy por encima del mínimo de 44 px.
      childAspectRatio: 1.6,
      children: [
        for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
          _Tecla(
            onTap: habilitado ? () => alPulsar(d) : null,
            child: Text(
              d,
              style: const TextStyle(
                fontFamily: AppTheme.monoFamily,
                fontSize: 25,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
            ),
          ),
        _Tecla(
          conFondo: false,
          onTap: habilitado ? alLimpiar : null,
          child: const Text(
            'LIMPIAR',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.secondary,
            ),
          ),
        ),
        _Tecla(
          onTap: habilitado ? () => alPulsar('0') : null,
          child: const Text(
            '0',
            style: TextStyle(
              fontFamily: AppTheme.monoFamily,
              fontSize: 25,
              fontWeight: FontWeight.w500,
              color: AppColors.primary,
            ),
          ),
        ),
        _Tecla(
          conFondo: false,
          onTap: habilitado ? alBorrar : null,
          child: const Icon(
            Icons.backspace_outlined,
            size: 24,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }
}

class _Tecla extends StatelessWidget {
  const _Tecla({required this.child, this.onTap, this.conFondo = true});

  final Widget child;
  final VoidCallback? onTap;
  final bool conFondo;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: conFondo
            ? const BoxDecoration(
                color: AppColors.background,
                border: Border.fromBorderSide(
                  BorderSide(color: AppColors.border),
                ),
              )
            : null,
        child: child,
      ),
    );
  }
}
