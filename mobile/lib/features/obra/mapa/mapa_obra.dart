import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/modelos/obra.dart';
import 'proveedor_de_teselas.dart';

/// El pin naranja del diseño; el de una obra cerrada va en gris.
const _naranjaDelPin = Color(0xFFEA580C);
const _grisDelPin = Color(0xFF94A3B8);

/// Cuántos tiles distintos pueden quedar sin llegar, **después de reintentar**,
/// antes de dar el mapa por perdido. La franja de la card (120 px) pide unos
/// cuatro: con uno solo faltando todavía se ve casi todo. La miniatura (64 px)
/// cabe en uno o dos: si no llega ninguno, ya no hay mapa.
const _tilesParaRendirseEnLaCard = 2;
const _tilesParaRendirseEnLaMiniatura = 1;

/// El mapa de una obra en su card (120 px de alto) o en una fila de la lista
/// (miniatura de 64 px): OpenStreetMap centrado en la obra, con su pin.
///
/// No se mueve ni se acerca —la card tiene que seguir siendo tocable y la
/// lista desplazable—; para elegir un lugar está la pantalla de ubicación.
///
/// Nunca deja una card rota:
/// * sin coordenadas, un placeholder «Sin ubicación todavía» (con botón para
///   marcarla, solo si [alMarcar] se da);
/// * si los tiles no cargan, un placeholder neutro con el pin y la dirección en
///   texto.
class MapaObra extends ConsumerStatefulWidget {
  const MapaObra({
    super.key,
    required this.obra,
    this.miniatura = false,
    this.alMarcar,
  });

  final Obra obra;

  /// 64×64 en vez de 120 de alto y todo el ancho.
  final bool miniatura;

  /// Abre el marcado de la ubicación. Solo se pasa para quien puede hacerlo
  /// (el admin): sin él, el placeholder no lleva botón.
  final VoidCallback? alMarcar;

  @override
  ConsumerState<MapaObra> createState() => _MapaObraState();
}

class _MapaObraState extends ConsumerState<MapaObra> {
  /// Cuántos reintentos van. Cada uno vuelve a pedir la capa de tiles: los que
  /// ya llegaron salen del caché de imágenes y solo se piden de nuevo los que
  /// fallaron.
  int _reintentos = 0;

  /// Los tiles que fallaron en la vuelta actual (sin repetir).
  final _fallidos = <String>{};

  Timer? _espera;
  bool _sinRed = false;

  double get _alto => widget.miniatura ? 64 : 120;

  int get _tilesParaRendirse => widget.miniatura
      ? _tilesParaRendirseEnLaMiniatura
      : _tilesParaRendirseEnLaCard;

  @override
  void dispose() {
    _espera?.cancel();
    super.dispose();
  }

  void _alFallarUnTile(String tile) {
    if (_sinRed) return;
    _fallidos.add(tile);

    final esperas = ref.read(esperasDeReintentoDeTeselasProvider);
    if (_reintentos < esperas.length) {
      // Se espera a que termine la vuelta (los demás tiles también pueden
      // fallar) y se vuelve a pedir una sola vez, con espera creciente.
      _espera ??= Timer(esperas[_reintentos], _reintentar);
      return;
    }
    if (_fallidos.length < _tilesParaRendirse) return;
    // El callback puede llegar en medio de un cuadro: se avisa al terminarlo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _sinRed = true);
    });
  }

  void _reintentar() {
    _espera = null;
    if (!mounted) return;
    setState(() {
      _reintentos++;
      _fallidos.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.obra;
    final Widget contenido;
    if (!o.tieneUbicacion) {
      contenido = _SinUbicacion(
        miniatura: widget.miniatura,
        alMarcar: o.activa ? widget.alMarcar : null,
      );
    } else if (_sinRed) {
      contenido = _MapaNoDisponible(obra: o, miniatura: widget.miniatura);
    } else {
      contenido = _MapaConTeselas(
        obra: o,
        miniatura: widget.miniatura,
        reintentos: _reintentos,
        alFallarUnTile: _alFallarUnTile,
      );
    }

    return SizedBox(
      height: _alto,
      width: widget.miniatura ? _alto : double.infinity,
      child: ClipRect(child: contenido),
    );
  }
}

class _MapaConTeselas extends ConsumerWidget {
  const _MapaConTeselas({
    required this.obra,
    required this.miniatura,
    required this.reintentos,
    required this.alFallarUnTile,
  });

  final Obra obra;
  final bool miniatura;

  /// Cambia la clave de la capa en cada reintento: eso la reconstruye y vuelve
  /// a pedir lo que falta.
  final int reintentos;
  final void Function(String tile) alFallarUnTile;

  /// Luminancia: lo que hace falta para pasar un mapa a grises.
  static const _grises = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cerrada = !obra.activa;
    Widget mapa = FlutterMap(
      options: MapOptions(
        initialCenter: LatLng(obra.latitud!, obra.longitud!),
        initialZoom: miniatura ? 15 : 16,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none,
        ),
        backgroundColor: const Color(0xFFE8E4DC),
      ),
      children: [
        TileLayer(
          key: ValueKey('capa-$reintentos'),
          urlTemplate: urlDeTeselasOsm,
          userAgentPackageName: paqueteDeLaApp,
          tileProvider: ref.watch(proveedorDeTeselasProvider),
          // Solo los tiles que se ven: nada de precargar los de alrededor.
          panBuffer: 0,
          keepBuffer: 0,
          errorTileCallback: (tile, _, _) => alFallarUnTile(
            '${tile.coordinates.z}/${tile.coordinates.x}/${tile.coordinates.y}',
          ),
        ),
      ],
    );
    if (cerrada) {
      mapa = ColorFiltered(
        key: const ValueKey('mapa-en-grises'),
        colorFilter: _grises,
        child: mapa,
      );
    }

    return Semantics(
      image: true,
      container: true,
      label: 'Mapa de ${obra.nombre}',
      // La atribución y el pin son parte del dibujo: se anuncia el mapa entero
      // como una sola imagen, no cada pieza.
      excludeSemantics: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          mapa,
          Align(
            // La punta del pin queda justo en el centro, que es la obra.
            child: Transform.translate(
              offset: Offset(0, miniatura ? -12 : -18),
              child: PinDeMapa(
                key: const ValueKey('pin-de-mapa'),
                color: cerrada ? _grisDelPin : _naranjaDelPin,
                ancho: miniatura ? 18 : 28,
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: _Atribucion(miniatura: miniatura),
          ),
        ],
      ),
    );
  }
}

/// La atribución que la licencia de OpenStreetMap exige tener a la vista.
class _Atribucion extends StatelessWidget {
  const _Atribucion({required this.miniatura});

  final bool miniatura;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xD9FFFFFF),
      padding: EdgeInsets.symmetric(
        horizontal: miniatura ? 3 : 6,
        vertical: miniatura ? 0 : 2,
      ),
      child: Text(
        miniatura ? '© OSM' : '© OpenStreetMap',
        style: TextStyle(
          fontSize: miniatura ? 7.5 : 10,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

/// La obra todavía no se marcó en el mapa.
class _SinUbicacion extends StatelessWidget {
  const _SinUbicacion({required this.miniatura, required this.alMarcar});

  final bool miniatura;
  final VoidCallback? alMarcar;

  @override
  Widget build(BuildContext context) {
    final icono = Icon(
      Icons.location_off_outlined,
      size: miniatura ? 22 : 26,
      color: AppColors.secondary,
    );
    return _FondoNeutro(
      child: miniatura
          ? Center(child: icono)
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icono,
                const SizedBox(height: 8),
                Text(
                  'Sin ubicación todavía',
                  style: AppTexto.cuerpoChico.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
                if (alMarcar != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: alMarcar,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 30),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      foregroundColor: AppColors.accentFill,
                      side: const BorderSide(
                        color: AppColors.accentFill,
                        width: 1.5,
                      ),
                      shape: const RoundedRectangleBorder(),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Marcar en el mapa'),
                  ),
                ],
              ],
            ),
    );
  }
}

/// Sin red o con los tiles caídos: el pin y la dirección en texto, que sirve
/// igual para saber dónde queda la obra.
class _MapaNoDisponible extends StatelessWidget {
  const _MapaNoDisponible({required this.obra, required this.miniatura});

  final Obra obra;
  final bool miniatura;

  @override
  Widget build(BuildContext context) {
    final cerrada = !obra.activa;
    final pin = PinDeMapa(
      key: const ValueKey('pin-de-mapa'),
      color: cerrada ? _grisDelPin : _naranjaDelPin,
      ancho: miniatura ? 18 : 24,
    );
    return _FondoNeutro(
      child: miniatura
          ? Center(child: pin)
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                pin,
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    obra.ubicacion,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTexto.cuerpoChico.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// El fondo rayado de los placeholders del diseño.
class _FondoNeutro extends StatelessWidget {
  const _FondoNeutro({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF1F5F9), Color(0xFFE8EDF3)],
        ),
      ),
      child: child,
    );
  }
}

/// El pin del mapa: una gota con un círculo blanco, como en el diseño.
class PinDeMapa extends StatelessWidget {
  const PinDeMapa({super.key, required this.color, this.ancho = 28});

  final Color color;

  /// El alto es 36/28 del ancho.
  final double ancho;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(ancho, ancho * 36 / 28),
        painter: _PintorDelPin(color),
      ),
    );
  }
}

class _PintorDelPin extends CustomPainter {
  const _PintorDelPin(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // El dibujo original es de 28×36.
    canvas.scale(size.width / 28, size.height / 36);
    final gota = Path()
      ..moveTo(14, 35)
      ..cubicTo(14, 35, 3, 22.5, 3, 13.5)
      ..arcToPoint(const Offset(25, 13.5), radius: const Radius.circular(11))
      ..cubicTo(25, 22.5, 14, 35, 14, 35)
      ..close();
    canvas
      ..drawShadow(gota, const Color(0x590F172A), 2, false)
      ..drawPath(gota, Paint()..color = color)
      ..drawPath(
        gota,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
      )
      ..drawCircle(const Offset(14, 13.5), 4.4, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_PintorDelPin anterior) => anterior.color != color;
}
