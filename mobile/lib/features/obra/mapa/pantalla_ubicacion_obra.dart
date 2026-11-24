import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../core/formato.dart';
import '../../../core/network/errores.dart';
import '../../../core/network/idempotencia.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_forma.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/api/dominio_api.dart';
import '../../../data/api/geocodificador.dart';
import '../../../data/modelos/obra.dart';
import '../../../shared_widgets/estados.dart';
import '../../../shared_widgets/panel.dart';
import '../../../shared_widgets/presion.dart';
import '../obra_activa.dart';
import 'mapa_obra.dart';
import 'proveedor_de_teselas.dart';

/// Dónde se parte cuando la obra todavía no tiene ubicación: Santiago.
const _santiago = LatLng(-33.4489, -70.6693);

/// El zoom de partida: se distingue una cuadra.
const _zoomInicial = 16.0;
const _zoomMinimo = 4.0;
const _zoomMaximo = 19.0;

/// Marcar dónde está una obra (solo ADMIN).
///
/// El pin queda fijo en el centro y **el mapa se mueve debajo**: lo que se
/// guarda es lo que está bajo el pin, no una dirección de texto. La búsqueda de
/// dirección sirve para llegar rápido a la zona; después se afina arrastrando.
///
/// La búsqueda va a Nominatim y respeta su política de uso: solo al enviar (no
/// hay autocompletado), una por segundo (lo cuida el geocodificador).
class PantallaUbicacionObra extends ConsumerStatefulWidget {
  const PantallaUbicacionObra({super.key, required this.obra});

  final Obra obra;

  @override
  ConsumerState<PantallaUbicacionObra> createState() =>
      _PantallaUbicacionObraState();
}

/// Qué hay entre el campo de búsqueda y el mapa.
sealed class _Busqueda {
  const _Busqueda();
}

class _Buscando extends _Busqueda {
  const _Buscando();
}

class _ConResultados extends _Busqueda {
  const _ConResultados(this.direcciones);
  final List<Direccion> direcciones;
}

class _SinResultados extends _Busqueda {
  const _SinResultados();
}

class _FalloLaBusqueda extends _Busqueda {
  const _FalloLaBusqueda(this.mensaje);
  final String mensaje;
}

class _PantallaUbicacionObraState extends ConsumerState<PantallaUbicacionObra> {
  final _campo = TextEditingController();
  final _mapa = MapController();
  final _intento = IntentoIdempotente();

  late LatLng _centro = widget.obra.tieneUbicacion
      ? LatLng(widget.obra.latitud!, widget.obra.longitud!)
      : _santiago;

  /// La dirección que se muestra como elegida: la de la obra al abrir, la del
  /// resultado que se toque después, y ninguna si se movió el mapa a mano.
  late String? _direccion = widget.obra.tieneUbicacion
      ? widget.obra.ubicacion
      : null;

  _Busqueda? _busqueda;

  /// Una respuesta que llega tarde, de una búsqueda anterior, no vale.
  int _turno = 0;

  bool _guardando = false;
  String? _errorAlGuardar;

  @override
  void dispose() {
    _campo.dispose();
    _mapa.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final texto = _campo.text.trim();
    if (texto.isEmpty) return;
    FocusScope.of(context).unfocus();
    final turno = ++_turno;
    setState(() => _busqueda = const _Buscando());
    _Busqueda resultado;
    try {
      final lista = await ref.read(geocodificadorProvider).buscar(texto);
      resultado = lista.isEmpty
          ? const _SinResultados()
          : _ConResultados(lista);
    } on DioException catch (e) {
      resultado = _FalloLaBusqueda(
        e.response?.statusCode == 429
            ? 'Demasiadas búsquedas seguidas. Espera un momento e inténtalo '
                  'de nuevo.'
            : 'No pudimos buscar la dirección. Revisa tu conexión e '
                  'inténtalo de nuevo.',
      );
    } catch (_) {
      resultado = const _FalloLaBusqueda(
        'No pudimos buscar la dirección. Inténtalo de nuevo.',
      );
    }
    if (!mounted || turno != _turno) return;
    setState(() => _busqueda = resultado);
  }

  void _elegir(Direccion d) {
    final destino = LatLng(d.latitud, d.longitud);
    setState(() {
      _centro = destino;
      _direccion = d.nombre;
      _busqueda = null;
    });
    _mapa.move(destino, _zoomInicial);
  }

  void _alMoverseElMapa(MapCamera camara, bool porUnGesto) {
    // Un movimiento programático (elegir un resultado, los botones de zoom)
    // ya actualizó el estado; solo importa lo que el usuario arrastra.
    setState(() {
      _centro = camara.center;
      if (porUnGesto) _direccion = null;
    });
  }

  void _zoom(double delta) {
    final camara = _mapa.camera;
    _mapa.move(
      camara.center,
      (camara.zoom + delta).clamp(_zoomMinimo, _zoomMaximo),
    );
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    setState(() {
      _guardando = true;
      _errorAlGuardar = null;
    });
    final lat = _centro.latitude;
    final lon = _centro.longitude;
    try {
      await ref
          .read(obrasApiProvider)
          .actualizarUbicacion(
            widget.obra.id,
            latitud: lat,
            longitud: lon,
            clave: _intento.clavePara([widget.obra.id, lat, lon]),
          );
      _intento.reiniciar();
      ref.invalidate(todasLasObrasProvider);
      ref.invalidate(obrasActivasProvider);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final mensajero = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      mensajero.showSnackBar(
        const SnackBar(content: Text('Ubicación guardada')),
      );
    } catch (e) {
      if (mounted) setState(() => _errorAlGuardar = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ubicación de la obra'),
            Text(
              widget.obra.nombre,
              style: const TextStyle(
                fontFamily: AppTheme.monoFamily,
                fontSize: 11.5,
                fontWeight: FontWeight.w400,
                color: AppColors.textOnDarkMuted,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _CampoDeBusqueda(
                controlador: _campo,
                alBuscar: _buscar,
                ocupado: _busqueda is _Buscando,
              ),
            ),
            if (_busqueda != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: _Resultados(
                  estado: _busqueda!,
                  alElegir: _elegir,
                  alReintentar: _buscar,
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: _MapaDeEleccion(
                  controlador: _mapa,
                  centro: _centro,
                  conUbicacionPrevia: widget.obra.tieneUbicacion,
                  alMoverse: _alMoverseElMapa,
                  alAcercar: () => _zoom(1),
                  alAlejar: () => _zoom(-1),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: _UbicacionElegida(direccion: _direccion, centro: _centro),
            ),
            if (_errorAlGuardar != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: MensajeError(mensaje: _errorAlGuardar!),
              ),
            Container(
              color: AppColors.card,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: BotonEnvio(
                texto: 'Usar esta ubicación',
                textoEnviando: 'Guardando…',
                enviando: _guardando,
                alPresionar: _guardar,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CampoDeBusqueda extends StatelessWidget {
  const _CampoDeBusqueda({
    required this.controlador,
    required this.alBuscar,
    required this.ocupado,
  });

  final TextEditingController controlador;
  final VoidCallback alBuscar;
  final bool ocupado;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey('busqueda-direccion'),
      controller: controlador,
      textInputAction: TextInputAction.search,
      // Solo al enviar: Nominatim no admite buscar mientras se escribe.
      onSubmitted: (_) => alBuscar(),
      autocorrect: false,
      decoration: InputDecoration(
        hintText: 'Buscar una dirección',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: IconButton(
          tooltip: 'Buscar dirección',
          icon: const Icon(Icons.arrow_forward),
          onPressed: ocupado ? null : alBuscar,
        ),
      ),
    );
  }
}

/// Lo que respondió la búsqueda, entre el campo y el mapa.
class _Resultados extends StatelessWidget {
  const _Resultados({
    required this.estado,
    required this.alElegir,
    required this.alReintentar,
  });

  final _Busqueda estado;
  final void Function(Direccion) alElegir;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    return switch (estado) {
      _Buscando() => Semantics(
        liveRegion: true,
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accentFill,
              ),
            ),
            SizedBox(width: 12),
            Text('Buscando…', style: AppTexto.cuerpoChico),
          ],
        ),
      ),
      _SinResultados() => Semantics(
        liveRegion: true,
        child: Panel(
          child: Row(
            children: [
              const Icon(Icons.search_off, color: AppColors.secondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'No encontramos esa dirección. Prueba con la calle y la '
                  'comuna, o mueve el mapa hasta el lugar.',
                  style: AppTexto.cuerpoChico,
                ),
              ),
            ],
          ),
        ),
      ),
      _FalloLaBusqueda(:final mensaje) => MensajeError(
        mensaje: mensaje,
        alReintentar: alReintentar,
      ),
      _ConResultados(:final direcciones) => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 190),
        child: Panel(
          padding: EdgeInsets.zero,
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: direcciones.length,
            separatorBuilder: (_, _) =>
                const Divider(height: 1, color: AppColors.border),
            itemBuilder: (context, i) => InkWell(
              onTap: () => alElegir(direcciones[i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.place_outlined,
                      size: 20,
                      color: AppColors.secondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        direcciones[i].nombre,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTexto.cuerpoChico.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    };
  }
}

/// El mapa grande: se mueve y se acerca, bajo un pin que no se mueve.
class _MapaDeEleccion extends ConsumerWidget {
  const _MapaDeEleccion({
    required this.controlador,
    required this.centro,
    required this.conUbicacionPrevia,
    required this.alMoverse,
    required this.alAcercar,
    required this.alAlejar,
  });

  final MapController controlador;
  final LatLng centro;
  final bool conUbicacionPrevia;
  final void Function(MapCamera camara, bool porUnGesto) alMoverse;
  final VoidCallback alAcercar;
  final VoidCallback alAlejar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          FlutterMap(
            mapController: controlador,
            options: MapOptions(
              initialCenter: centro,
              initialZoom: _zoomInicial,
              minZoom: _zoomMinimo,
              maxZoom: _zoomMaximo,
              backgroundColor: const Color(0xFFE8E4DC),
              // Solo arrastrar y acercar: girar el mapa solo desorienta.
              interactionOptions: const InteractionOptions(
                flags:
                    InteractiveFlag.drag |
                    InteractiveFlag.pinchZoom |
                    InteractiveFlag.doubleTapZoom |
                    InteractiveFlag.flingAnimation,
              ),
              onPositionChanged: (camara, porUnGesto) =>
                  alMoverse(camara, porUnGesto),
            ),
            children: [
              TileLayer(
                urlTemplate: urlDeTeselasOsm,
                userAgentPackageName: paqueteDeLaApp,
                tileProvider: ref.watch(proveedorDeTeselasProvider),
                panBuffer: 0,
                keepBuffer: 1,
              ),
            ],
          ),
          Align(
            // La punta del pin en el centro: lo marcado es lo que está bajo ella.
            child: Transform.translate(
              offset: const Offset(0, -18),
              child: const PinDeMapa(
                key: ValueKey('pin-fijo'),
                color: Color(0xFFEA580C),
              ),
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: _BotonesDeZoom(alAcercar: alAcercar, alAlejar: alAlejar),
          ),
          const Positioned(right: 0, bottom: 0, child: _Atribucion()),
        ],
      ),
    );
  }
}

class _BotonesDeZoom extends StatelessWidget {
  const _BotonesDeZoom({required this.alAcercar, required this.alAlejar});

  final VoidCallback alAcercar;
  final VoidCallback alAlejar;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.borderControl),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Acercar',
            icon: const Icon(Icons.add),
            onPressed: alAcercar,
          ),
          const Divider(height: 1, color: AppColors.border),
          IconButton(
            tooltip: 'Alejar',
            icon: const Icon(Icons.remove),
            onPressed: alAlejar,
          ),
        ],
      ),
    );
  }
}

/// La atribución que la licencia de OpenStreetMap exige.
class _Atribucion extends StatelessWidget {
  const _Atribucion();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xD9FFFFFF),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: const Text(
        '© OpenStreetMap',
        style: TextStyle(fontSize: 10, color: AppColors.primary),
      ),
    );
  }
}

/// La dirección (si se sabe) y las coordenadas de lo que está bajo el pin.
class _UbicacionElegida extends StatelessWidget {
  const _UbicacionElegida({required this.direccion, required this.centro});

  final String? direccion;
  final LatLng centro;

  @override
  Widget build(BuildContext context) {
    final coordenadas =
        '${Formato.coordenada(centro.latitude)} · '
        '${Formato.coordenada(centro.longitude)}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border.fromBorderSide(BorderSide(color: AppColors.border)),
        borderRadius: AppForma.borde,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ubicación elegida', style: AppTexto.rotulo),
          const SizedBox(height: 4),
          Text(
            direccion ?? 'Punto marcado en el mapa',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTexto.subtitulo.copyWith(fontSize: 13.5),
          ),
          const SizedBox(height: 2),
          Text(
            coordenadas,
            style: const TextStyle(
              fontFamily: AppTheme.monoFamily,
              fontSize: 12,
              color: AppColors.secondary,
            ),
          ),
        ],
      ),
    );
  }
}
