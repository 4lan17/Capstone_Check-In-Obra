import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/modelos/alerta.dart';
import '../../data/modelos/kardex.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import 'bodega_providers.dart';
import 'pantalla_cierre_turno.dart';
import 'pantalla_escaneo.dart';
import 'pantalla_prestamo.dart';
import 'pantalla_solicitudes.dart';

/// Lo primero que ve el bodeguero: cómo va el turno y qué requiere atención.
class PantallaInicioBodega extends ConsumerWidget {
  const PantallaInicioBodega({super.key, required this.alIrA});

  /// Salta a otra pestaña del shell. Los accesos rápidos llevan a Bodega y a
  /// Alertas, que ya existen abajo: duplicar la pantalla sería duplicar el
  /// estado.
  final void Function(int indice) alIrA;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movimientosHoy = ref.watch(movimientosDeHoyProvider);
    final prestamos = ref.watch(prestamosAbiertosProvider);
    final alertas = ref.watch(alertasSinResolverProvider);

    return RefreshIndicator(
      onRefresh: () async => recargarBodega(ref),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Contador(
                          valor: '${movimientosHoy.valueOrNull?.length ?? 0}',
                          rotulo: 'Movimientos\ndel turno',
                        ),
                      ),
                      Expanded(
                        child: Contador(
                          valor: '${prestamos.valueOrNull?.length ?? 0}',
                          rotulo: 'Herramientas\nprestadas',
                        ),
                      ),
                      Expanded(
                        child: Contador(
                          valor: '${alertas.valueOrNull?.length ?? 0}',
                          rotulo: 'Alertas\nsin resolver',
                          color: (alertas.valueOrNull?.isEmpty ?? true)
                              ? AppColors.primary
                              : AppColors.destructiveDark,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                _BotonCierre(),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _Solicitudes(),
          const SizedBox(height: 20),
          const Etiqueta('Escanear'),
          const SizedBox(height: 8),
          // El escaneo va arriba de "Registrar" porque es por donde empieza el
          // trabajo del mesón: primero se identifica a quien viene a buscar
          // algo, o lo que trae en la mano, y recién después se elige qué
          // movimiento anotar.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _AccesoRapido(
                    icono: Icons.qr_code_scanner,
                    titulo: 'Credencial',
                    detalle: 'Ver y aprobar lo que pidió el trabajador',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PantallaEscaneoCredencial(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AccesoRapido(
                    icono: Icons.barcode_reader,
                    titulo: 'Código de barras',
                    detalle: 'Encontrar un material o una herramienta',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PantallaEscaneoCodigo(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Etiqueta('Capital en la obra'),
          const SizedBox(height: 8),
          const _ValorEnObra(),
          const SizedBox(height: 20),
          const Etiqueta('Registrar'),
          const SizedBox(height: 8),
          // Las dos tarjetas del mismo alto. `stretch` solo no basta dentro de
          // un ListView: la altura que entra no está acotada, así que no hay
          // contra qué estirarse. `IntrinsicHeight` mide primero la más alta y
          // recién ahí `stretch` iguala la otra.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _AccesoRapido(
                    icono: Icons.inventory_2_outlined,
                    titulo: 'Movimiento',
                    detalle: 'Recepción, despacho o consumo',
                    onTap: () => alIrA(1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AccesoRapido(
                    icono: Icons.handyman_outlined,
                    titulo: 'Préstamo',
                    detalle: 'Entregar una herramienta',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PantallaPrestamo(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(child: Etiqueta('Alertas sin resolver')),
              if ((alertas.valueOrNull ?? const []).isNotEmpty)
                TextButton(
                  onPressed: () => alIrA(3),
                  child: const Text('Ver todas'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Contenido<List<Alerta>>(
            valor: alertas,
            alReintentar: () => ref.invalidate(alertasProvider),
            estaVacio: (l) => l.isEmpty,
            vacio: const Panel(
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      Icons.check_circle_outline,
                      size: 20,
                      color: AppColors.successDark,
                    ),
                  ),
                  SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      'Nada pendiente en esta obra.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            constructor: (lista) => Column(
              children: [
                for (final alerta in lista.take(3)) ...[
                  _FilaAlertaResumen(alerta: alerta),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Etiqueta('Últimos movimientos'),
          const SizedBox(height: 8),
          Contenido<List<MovimientoKardex>>(
            valor: ref.watch(movimientosProvider),
            alReintentar: () => ref.invalidate(movimientosProvider),
            estaVacio: (l) => l.isEmpty,
            vacio: const Vacio(
              icono: Icons.receipt_long_outlined,
              titulo: 'Sin movimientos todavía',
              detalle:
                  'El kardex de esta obra está en blanco. La primera recepción '
                  'de material lo abre.',
            ),
            constructor: (lista) => Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < lista.take(5).length; i++)
                    _FilaMovimiento(
                      movimiento: lista[i],
                      ultima: i == lista.take(5).length - 1,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// La cola de solicitudes de la obra.
///
/// Va arriba de todo lo demás porque es gente esperando: el resto de la
/// pantalla son cifras que se pueden mirar en cualquier momento, esto no.
class _Solicitudes extends ConsumerWidget {
  const _Solicitudes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(solicitudesPendientesProvider);
    final pendientes = estado.valueOrNull;
    final fallo = estado.hasError;
    final hayGenteEsperando = (pendientes ?? 0) > 0;

    // Si la consulta falló, el panel no puede quedarse diciendo "cargando":
    // tocarlo reintenta en vez de llevar a una lista que tampoco va a cargar.
    void reintentar() {
      ref.invalidate(solicitudesMaterialProvider);
      ref.invalidate(solicitudesHerramientaProvider);
    }

    final (fondo, borde, colorTexto) = switch ((fallo, hayGenteEsperando)) {
      (true, _) => (
        AppColors.destructiveTint,
        AppColors.destructive,
        AppColors.destructiveDark,
      ),
      (_, true) => (
        AppColors.warningTint,
        AppColors.warning,
        AppColors.warningDark,
      ),
      _ => (AppColors.card, AppColors.borderControl, AppColors.secondary),
    };

    return PanelTocable(
      semanticLabel: switch ((fallo, pendientes)) {
        (true, _) =>
          'No se pudieron cargar las solicitudes. Tocar para reintentar',
        (_, null) => 'Solicitudes pendientes, cargando',
        (_, 0) => 'Solicitudes: ninguna pendiente. Tocar para ver la cola',
        (_, 1) => '1 solicitud pendiente. Tocar para resolverla',
        (_, final n) => '$n solicitudes pendientes. Tocar para resolverlas',
      },
      borderColor: borde,
      color: fondo,
      onTap: fallo
          ? reintentar
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const PantallaSolicitudesObra(),
              ),
            ),
      child: Row(
        children: [
          Icon(
            fallo ? Icons.error_outline : Icons.inbox_outlined,
            size: 22,
            color: fallo || hayGenteEsperando
                ? colorTexto
                : AppColors.secondary,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Solicitudes',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  switch ((fallo, pendientes)) {
                    (true, _) => 'No se pudieron cargar. Toca para reintentar.',
                    (_, null) => 'Cargando…',
                    (_, 0) => 'Nadie está esperando material ni herramientas',
                    (_, 1) => '1 trabajador espera respuesta',
                    (_, final n) => '$n solicitudes esperan respuesta',
                  },
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: colorTexto,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            fallo ? Icons.refresh : Icons.chevron_right,
            size: 22,
            color: AppColors.accentFill,
          ),
        ],
      ),
    );
  }
}

/// Cuánta plata está parada en la obra, separada en dos cifras.
///
/// Se muestran aparte porque son problemas distintos: el material en bodega es
/// capital inmovilizado que hay que consumir, y las herramientas afuera son
/// valor que hay que recuperar antes de cerrar el turno. Un solo total las
/// volvería una cifra decorativa.
class _ValorEnObra extends ConsumerWidget {
  const _ValorEnObra();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final valor = ref.watch(valorEnObraProvider);

    return Contenido<ValorEnObra>(
      valor: valor,
      alReintentar: () => recargarBodega(ref),
      constructor: (v) => Panel(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _FilaValor(
              icono: Icons.inventory_2_outlined,
              titulo: 'Materiales en bodega',
              detalle: 'Stock actual valorizado a precio de catálogo',
              monto: v.materialesEnBodega,
            ),
            const Divider(height: 1, color: AppColors.border),
            _FilaValor(
              icono: Icons.handyman_outlined,
              titulo: 'Herramientas fuera',
              detalle: switch (v.herramientasPrestadas) {
                0 => 'Todas en bodega',
                1 => '1 prestada · valor de reposición',
                final n => '$n prestadas · valor de reposición',
              },
              monto: v.herramientasFuera,
              alerta: v.herramientasPrestadas > 0,
              ultima: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaValor extends StatelessWidget {
  const _FilaValor({
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.monto,
    this.alerta = false,
    this.ultima = false,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final double monto;
  final bool alerta;
  final bool ultima;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$titulo: ${Formato.pesos(monto)}. $detalle',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(icono, size: 20, color: AppColors.secondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detalle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              Formato.pesos(monto),
              style: TextStyle(
                fontFamily: AppTheme.monoFamily,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: alerta ? AppColors.warningDark : AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BotonCierre extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fuera = ref.watch(prestamosAbiertosProvider).valueOrNull?.length ?? 0;

    return PanelTocable(
      semanticLabel: 'Cerrar el turno de bodega',
      borderColor: Colors.transparent,
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const PantallaCierreTurno())),
      child: Row(
        children: [
          const Icon(
            Icons.nightlight_outlined,
            size: 20,
            color: AppColors.secondary,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cerrar turno',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  fuera == 0
                      ? 'No hay herramientas fuera de bodega'
                      : '$fuera ${fuera == 1 ? 'herramienta sigue' : 'herramientas siguen'} fuera',
                  style: TextStyle(
                    fontSize: 12,
                    color: fuera == 0
                        ? AppColors.secondary
                        : AppColors.warningDark,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            size: 20,
            color: AppColors.accentFill,
          ),
        ],
      ),
    );
  }
}

class _AccesoRapido extends StatelessWidget {
  const _AccesoRapido({
    required this.icono,
    required this.titulo,
    required this.detalle,
    required this.onTap,
  });

  final IconData icono;
  final String titulo;
  final String detalle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PanelTocable(
      semanticLabel: '$titulo. $detalle',
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 24, color: AppColors.accentFill),
          const SizedBox(height: 12),
          Text(
            titulo,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            detalle,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.3,
              color: AppColors.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaAlertaResumen extends StatelessWidget {
  const _FilaAlertaResumen({required this.alerta});

  final Alerta alerta;

  @override
  Widget build(BuildContext context) {
    return Panel(
      borderIzquierdo: switch (alerta.tipo) {
        'NO_DEVUELTA' => AppColors.destructive,
        'STOCK_CRITICO' => AppColors.warning,
        _ => AppColors.secondary,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ChipEstado.critico(nombreDeAlerta(alerta.tipo)),
              const Spacer(),
              Text(
                Formato.antiguedad(alerta.fecha),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            alerta.mensaje,
            style: const TextStyle(
              fontSize: 13,
              height: 1.35,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaMovimiento extends StatelessWidget {
  const _FilaMovimiento({required this.movimiento, required this.ultima});

  final MovimientoKardex movimiento;
  final bool ultima;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: ultima
            ? null
            : const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _ChipTipo(tipo: movimiento.tipo),
                    const SizedBox(width: 8),
                    Text(
                      Formato.relativa(movimiento.fecha),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  movimiento.materialNombre,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.primary,
                  ),
                ),
                if (movimiento.receptor case final quien?) ...[
                  const SizedBox(height: 3),
                  Text(
                    'a $quien',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            Formato.cantidadConSigno(movimiento.cantidadConSigno),
            style: TextStyle(
              fontFamily: AppTheme.monoFamily,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: movimiento.entra
                  ? AppColors.successDark
                  : AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipTipo extends StatelessWidget {
  const _ChipTipo({required this.tipo});

  final String tipo;

  @override
  Widget build(BuildContext context) => switch (tipo) {
    'RECEPCION' => ChipEstado.exito('Recepción', conPunto: false),
    'DESPACHO' => ChipEstado.neutro('Despacho'),
    _ => ChipEstado.aviso('Consumo', conPunto: false),
  };
}
