import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/network/errores.dart';
import '../../core/network/idempotencia.dart';
import '../../core/pantalla.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_forma.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/perfil_trabajador.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import 'codigo_credencial_controller.dart';
import 'trabajador_providers.dart';

/// La credencial que se muestra en el mesón de bodega.
///
/// Es lo único de esta app que se usa con el teléfono en la mano de otra
/// persona —el bodeguero lo escanea—, así que el QR ocupa el ancho entero, va
/// sobre blanco puro con su margen de silencio y nada se le superpone. Debajo
/// van el código para tipearlo y nombre y RUT en grande, para que el bodeguero
/// confirme de un vistazo que la cara coincide con la credencial.
///
/// El QR lleva un **código de vida corta** (2 minutos) que se pide al abrir la
/// pestaña y se renueva solo: una captura de pantalla no sirve, y sin conexión
/// no hay credencial que mostrar en vez de una que ya no vale.
class PantallaCredencial extends ConsumerStatefulWidget {
  const PantallaCredencial({super.key, this.activa = true});

  /// Si la pestaña se está viendo. Las pestañas viven todas montadas, así que
  /// sin esto el código se pediría y renovaría también con otra pestaña
  /// abierta: cada código emitido en vano es uno más que alguien podría haber
  /// capturado.
  final bool activa;

  @override
  ConsumerState<PantallaCredencial> createState() => _PantallaCredencialState();
}

class _PantallaCredencialState extends ConsumerState<PantallaCredencial>
    with WidgetsBindingObserver {
  late final CodigoCredencialNotifier _codigo = ref.read(
    codigoCredencialProvider.notifier,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.activa) _despues(_codigo.activar);
  }

  @override
  void didUpdateWidget(PantallaCredencial anterior) {
    super.didUpdateWidget(anterior);
    if (widget.activa == anterior.activa) return;
    _despues(widget.activa ? _codigo.activar : _codigo.desactivar);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    if (estado == AppLifecycleState.resumed) _codigo.alReanudar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _codigo.desactivar();
    super.dispose();
  }

  /// Cambiar un provider no se puede mientras el árbol se construye.
  void _despues(VoidCallback accion) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) accion();
    });
  }

  @override
  Widget build(BuildContext context) {
    final perfil = ref.watch(perfilTrabajadorProvider);
    final codigo = ref.watch(codigoCredencialProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(perfilTrabajadorProvider);
        await ref.read(perfilTrabajadorProvider.future);
        await _codigo.reintentar();
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
                _Tarjeta(
                  perfil: p,
                  codigo: codigo,
                  cargando: widget.activa,
                  alReintentar: _codigo.reintentar,
                ),
                if (codigo is CodigoVigente) ...[
                  const SizedBox(height: AppEspacio.md),
                  FilledButton.icon(
                    onPressed: () => mostrarCredencialCompleta(context, p),
                    icon: const Icon(Icons.fullscreen),
                    label: const Text('Mostrar en bodega'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ],
                const SizedBox(height: AppEspacio.md),
                Text(
                  'Muéstrala en bodega para retirar lo que pediste o para que '
                  'te presten una herramienta. El código cambia solo cada '
                  'minuto: una captura de pantalla no sirve. Si el lector no '
                  'lo toma, dicta el código de abajo.',
                  textAlign: TextAlign.center,
                  style: AppTexto.cuerpoChico,
                ),
                const SizedBox(height: AppEspacio.xl),
                // Renovar necesita al servidor: sin conexión solo confundiría.
                if (!p.sinConexion) _Renovar(perfil: p),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tarjeta extends StatelessWidget {
  const _Tarjeta({
    required this.perfil,
    required this.codigo,
    required this.cargando,
    required this.alReintentar,
  });

  final PerfilTrabajador perfil;
  final EstadoCodigo codigo;

  /// Si se está pidiendo el código. En una pestaña que no se ve no se pide
  /// nada, y un indicador girando ahí no tiene a quién avisarle.
  final bool cargando;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    final p = perfil;

    return Panel(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        children: [
          switch (codigo) {
            final CodigoVigente vigente => GestureDetector(
              onTap: () => mostrarCredencialCompleta(context, p),
              child: _CodigoVigente(codigo: vigente, ladoMaximo: 300),
            ),
            CodigoCargando() => _CargandoCodigo(girando: cargando),
            CodigoNoDisponible(:final mensaje, :final sinConexion) =>
              _SinCodigo(
                mensaje: mensaje,
                sinConexion: sinConexion,
                alReintentar: alReintentar,
              ),
          },
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

/// El QR del código vigente, el código en texto para tipearlo y cuánto falta
/// para que venza.
class _CodigoVigente extends StatelessWidget {
  const _CodigoVigente({required this.codigo, this.ladoMaximo});

  final CodigoVigente codigo;

  /// Tope del lado del QR; `null` en pantalla completa, donde manda el espacio.
  final double? ladoMaximo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          // Topado a 300 en la tarjeta: más grande no se lee mejor y empuja el
          // nombre fuera de la pantalla en un teléfono chico.
          builder: (context, c) => Center(
            child: CodigoQr(
              codigo: codigo.codigo.codigo,
              lado: c.maxWidth.clamp(180.0, ladoMaximo ?? c.maxWidth),
            ),
          ),
        ),
        const SizedBox(height: AppEspacio.md),
        TextoDelCodigo(codigo: codigo.codigo.agrupado),
        const SizedBox(height: AppEspacio.sm),
        Vigencia(codigo: codigo),
      ],
    );
  }
}

/// `K7M2-9QXP` en grande y monoespaciado, para dictarlo o tipearlo sin
/// confundir una letra con otra.
class TextoDelCodigo extends StatelessWidget {
  const TextoDelCodigo({super.key, required this.codigo, this.tamano = 30});

  final String codigo;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // Un lector de pantalla leería "K7M2" como una palabra: se deletrea.
      label:
          'Código de tu credencial: ${codigo.replaceAll('-', ', ').split('').join(' ')}',
      excludeSemantics: true,
      child: Text(
        codigo,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: AppTheme.monoFamily,
          fontSize: tamano,
          fontWeight: FontWeight.w700,
          letterSpacing: 3,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

/// Cuánto falta para que venza: una barra que se vacía y el tiempo en texto.
class Vigencia extends StatelessWidget {
  const Vigencia({super.key, required this.codigo});

  final CodigoVigente codigo;

  @override
  Widget build(BuildContext context) {
    final porVencer = codigo.restante <= 20;
    final color = porVencer ? AppColors.warningDark : AppColors.secondary;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: codigo.proporcion,
            minHeight: 6,
            backgroundColor: AppColors.sunken,
            color: porVencer ? AppColors.warning : AppColors.accentFill,
          ),
        ),
        const SizedBox(height: 6),
        // Cambia cada segundo: leerlo en voz alta cada vez sería un estorbo.
        ExcludeSemantics(
          child: Text(
            'Vence en ${codigo.restanteTexto}',
            style: AppTexto.cuerpoChico.copyWith(
              color: color,
              fontFeatures: AppTexto.tabulares,
            ),
          ),
        ),
      ],
    );
  }
}

class _CargandoCodigo extends StatelessWidget {
  const _CargandoCodigo({required this.girando});

  final bool girando;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.sunken,
        borderRadius: AppForma.borde,
      ),
      child: girando
          ? const CircularProgressIndicator(color: AppColors.accentFill)
          : null,
    );
  }
}

/// En lugar del QR cuando no hay un código vigente: no se muestra nada que
/// parezca una credencial.
class _SinCodigo extends StatelessWidget {
  const _SinCodigo({
    required this.mensaje,
    required this.sinConexion,
    required this.alReintentar,
  });

  final String mensaje;
  final bool sinConexion;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppEspacio.md),
        decoration: const BoxDecoration(
          color: AppColors.sunken,
          borderRadius: AppForma.borde,
        ),
        child: Column(
          children: [
            Icon(
              sinConexion ? Icons.cloud_off : Icons.error_outline,
              size: 40,
              color: AppColors.secondary,
            ),
            const SizedBox(height: AppEspacio.sm + 4),
            Text(mensaje, textAlign: TextAlign.center, style: AppTexto.cuerpo),
            const SizedBox(height: AppEspacio.sm),
            TextButton.icon(
              onPressed: alReintentar,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renovar revoca los códigos vigentes. Se ofrece abajo y con confirmación: es
/// para cuando se perdió el teléfono o alguien vio el código, no algo que se
/// toque por curiosidad.
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
          'Los códigos vigentes dejan de servir de inmediato, incluida cualquier '
          'captura o foto que alguien tenga. Hazlo si perdiste el teléfono o '
          'crees que otra persona lo está usando.',
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
            // Reintentar tras un timeout repite la misma renovación, no hace
            // dos.
            clave: _intento.clavePara([widget.perfil.id, 'renovar']),
          );
      _intento.reiniciar();
      ref.invalidate(perfilTrabajadorProvider);
      // El código de la pantalla acaba de quedar sin efecto: se pide otro.
      unawaited(ref.read(codigoCredencialProvider.notifier).renovarAhora());
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Credencial renovada. Los códigos anteriores ya no sirven.',
          ),
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

/// El QR sobre blanco puro con su margen de silencio: lo mismo en la tarjeta,
/// a pantalla completa y en el pedido de herramientas.
class CodigoQr extends StatelessWidget {
  const CodigoQr({
    super.key,
    required this.codigo,
    required this.lado,
    this.etiqueta = 'Código QR de tu credencial',
  });

  final String codigo;
  final double lado;

  /// Qué es, para el lector de pantalla.
  final String etiqueta;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: etiqueta,
      child: Container(
        color: Colors.white,
        child: QrImageView(
          data: codigo,
          size: lado,
          // El margen blanco alrededor es parte del código: sin él, el
          // escáner confunde el borde de la tarjeta con un módulo.
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
      ),
    );
  }
}

/// Abre la credencial a pantalla completa.
Future<void> mostrarCredencialCompleta(
  BuildContext context,
  PerfilTrabajador perfil,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => PantallaCredencialCompleta(perfil: perfil),
  ),
);

/// La credencial como la ve el bodeguero: solo el código, el nombre y el RUT,
/// sobre blanco, sin barras del sistema y con el brillo al máximo. Se cierra
/// con un toque en cualquier parte: el trabajador tiene guantes.
///
/// Muestra el mismo código en vivo que la pestaña: se renueva solo y, si no se
/// puede renovar y vence, lo dice en vez de dejar un QR que ya no sirve.
class PantallaCredencialCompleta extends ConsumerStatefulWidget {
  const PantallaCredencialCompleta({super.key, required this.perfil});

  final PerfilTrabajador perfil;

  @override
  ConsumerState<PantallaCredencialCompleta> createState() =>
      _PantallaCredencialCompletaState();
}

class _PantallaCredencialCompletaState
    extends ConsumerState<PantallaCredencialCompleta> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    Pantalla.brilloMaximo();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Pantalla.brilloNormal();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.perfil;
    final codigo = ref.watch(codigoCredencialProvider);
    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              // Lo más grande que quepa dejando sitio al código y al nombre
              // debajo. Sin bajar de 180: más chico el lector ya no lo toma.
              final lado = math.max(
                180.0,
                math.min(c.maxWidth - 32, c.maxHeight - 290),
              );
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  switch (codigo) {
                    final CodigoVigente vigente => Column(
                      children: [
                        CodigoQr(codigo: vigente.codigo.codigo, lado: lado),
                        const SizedBox(height: AppEspacio.md),
                        TextoDelCodigo(
                          codigo: vigente.codigo.agrupado,
                          tamano: 34,
                        ),
                        const SizedBox(height: AppEspacio.sm),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 48),
                          child: Vigencia(codigo: vigente),
                        ),
                      ],
                    ),
                    CodigoCargando() => const SizedBox(
                      height: 200,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.accentFill,
                        ),
                      ),
                    ),
                    CodigoNoDisponible(:final mensaje) => Padding(
                      padding: const EdgeInsets.all(AppEspacio.lg),
                      child: Text(
                        mensaje,
                        textAlign: TextAlign.center,
                        style: AppTexto.titulo.copyWith(fontSize: 20),
                      ),
                    ),
                  },
                  const SizedBox(height: AppEspacio.lg),
                  Text(
                    p.nombre,
                    textAlign: TextAlign.center,
                    style: AppTexto.titulo.copyWith(fontSize: 26),
                  ),
                  if (p.rut != null)
                    Text(
                      p.rut!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFeatures: AppTexto.tabulares,
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textMuted,
                      ),
                    ),
                  const SizedBox(height: AppEspacio.xl),
                  Text('Toca para cerrar', style: AppTexto.cuerpoChico),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
