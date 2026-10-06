import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/network/errores.dart';
import '../../core/network/idempotencia.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_forma.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/perfil_trabajador.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import 'trabajador_providers.dart';

/// La credencial que se muestra en el mesón de bodega.
///
/// Es lo único de esta app que se usa con el teléfono en la mano de otra
/// persona —el bodeguero lo escanea—, así que el QR ocupa el ancho entero, va
/// sobre blanco puro con su margen de silencio y nada se le superpone. Debajo
/// van nombre y RUT en grande, para que el bodeguero confirme de un vistazo
/// que la cara coincide con la credencial.
class PantallaCredencial extends ConsumerWidget {
  const PantallaCredencial({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilTrabajadorProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(perfilTrabajadorProvider);
        await ref.read(perfilTrabajadorProvider.future);
      },
      child: ListView(
        padding: AppEspacio.pantalla,
        children: [
          Contenido<PerfilTrabajador>(
            valor: perfil,
            alReintentar: () => ref.invalidate(perfilTrabajadorProvider),
            constructor: (p) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Tarjeta(perfil: p),
                const SizedBox(height: AppEspacio.md),
                Text(
                  'Muéstrala en bodega para retirar lo que pediste o para que '
                  'te presten una herramienta. Si no la lee, sube el brillo '
                  'de la pantalla.',
                  textAlign: TextAlign.center,
                  style: AppTexto.cuerpoChico,
                ),
                const SizedBox(height: AppEspacio.xl),
                _Renovar(perfil: p),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({required this.perfil});

  final PerfilTrabajador perfil;

  @override
  Widget build(BuildContext context) {
    final p = perfil;
    final codigo = p.credencialQr;

    return Panel(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        children: [
          if (codigo == null)
            const _SinCredencial()
          else
            Semantics(
              image: true,
              label: 'Código QR de tu credencial',
              child: LayoutBuilder(
                builder: (context, c) {
                  // Topado a 300: más grande no se lee mejor y empuja el
                  // nombre fuera de la pantalla en un teléfono chico.
                  final lado = c.maxWidth.clamp(180.0, 300.0);
                  return Container(
                    color: Colors.white,
                    child: QrImageView(
                      data: codigo,
                      size: lado,
                      // El margen blanco alrededor es parte del código: sin
                      // él, el escáner confunde el borde de la tarjeta con
                      // un módulo.
                      padding: const EdgeInsets.all(12),
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF0F172A),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xFF0F172A),
                      ),
                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: AppEspacio.md),
          Text(
            p.nombre,
            textAlign: TextAlign.center,
            style: AppTexto.titulo.copyWith(fontSize: 22),
          ),
          if (p.rut != null) ...[
            const SizedBox(height: 2),
            Text(
              p.rut!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFeatures: AppTexto.tabulares,
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: AppColors.textMuted,
              ),
            ),
          ],
          const SizedBox(height: AppEspacio.sm + 4),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              if (p.obraNombre != null) ChipEstado.neutro(p.obraNombre!),
              if (p.cuadrillaNombre != null)
                ChipEstado.neutro(p.cuadrillaNombre!),
              if (!p.tieneObra) ChipEstado.aviso('Sin cuadrilla asignada'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SinCredencial extends StatelessWidget {
  const _SinCredencial();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.sunken,
        borderRadius: AppForma.borde,
      ),
      padding: const EdgeInsets.all(AppEspacio.md),
      child: Text(
        'Todavía no tienes credencial. Tira hacia abajo para pedirla, o '
        'avísale al administrador.',
        textAlign: TextAlign.center,
        style: AppTexto.cuerpoChico,
      ),
    );
  }
}

/// Renovar anula el código anterior. Se ofrece abajo y con confirmación: es
/// para cuando se perdió el teléfono o alguien fotografió el código, no algo
/// que se toque por curiosidad.
class _Renovar extends ConsumerStatefulWidget {
  const _Renovar({required this.perfil});

  final PerfilTrabajador perfil;

  @override
  ConsumerState<_Renovar> createState() => _RenovarState();
}

class _RenovarState extends ConsumerState<_Renovar> {
  bool _enviando = false;
  final _intento = IntentoIdempotente();

  Future<void> _renovar() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Renovar tu credencial?'),
        content: const Text(
          'El código actual deja de servir de inmediato, incluida cualquier '
          'captura o foto que alguien tenga de él. Hazlo si perdiste el '
          'teléfono o crees que otra persona lo está usando.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Renovar'),
          ),
        ],
      ),
    );
    if (confirmado != true || _enviando) return;

    setState(() => _enviando = true);
    try {
      await ref
          .read(trabajadoresApiProvider)
          .renovarMiCredencial(
            // La huella es el código que se quiere anular: reintentar tras un
            // timeout repite la misma renovación, no emite dos.
            clave: _intento.clavePara([widget.perfil.credencialQr]),
          );
      _intento.reiniciar();
      ref.invalidate(perfilTrabajadorProvider);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Credencial renovada. La anterior ya no sirve.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensajeDeError(e))));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: _enviando ? null : _renovar,
        icon: _enviando
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.autorenew, size: 18),
        label: Text(_enviando ? 'Renovando…' : 'Perdí el teléfono: renovar'),
        style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
      ),
    );
  }
}
