package cl.duocuc.checkinobra.presupuesto;

import cl.duocuc.checkinobra.cubicacion.ItemCubicado;
import cl.duocuc.checkinobra.cubicacion.ItemCubicadoRepository;
import cl.duocuc.checkinobra.cubicacion.Partida;
import cl.duocuc.checkinobra.cubicacion.PartidaRepository;
import cl.duocuc.checkinobra.inventario.KardexMovimiento;
import cl.duocuc.checkinobra.inventario.KardexMovimientoRepository;
import cl.duocuc.checkinobra.inventario.TipoMovimiento;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * ComparadorPresupuesto «service» del diagrama —
 * compararVsEjecutado(p: Presupuesto): ReporteDesviacion.
 */
@Service
@Transactional(readOnly = true)
public class ComparadorPresupuestoService {

    private final KardexMovimientoRepository kardexMovimientoRepository;
    private final PartidaRepository partidaRepository;
    private final ItemCubicadoRepository itemCubicadoRepository;

    public ComparadorPresupuestoService(
            KardexMovimientoRepository kardexMovimientoRepository,
            PartidaRepository partidaRepository,
            ItemCubicadoRepository itemCubicadoRepository) {
        this.kardexMovimientoRepository = kardexMovimientoRepository;
        this.partidaRepository = partidaRepository;
        this.itemCubicadoRepository = itemCubicadoRepository;
    }

    public ReporteDesviacion compararVsEjecutado(Presupuesto presupuesto) {
        Long obraId = presupuesto.getObra().getId();
        double presupuestado = presupuesto.getTotal();

        List<KardexMovimiento> movimientosObra = kardexMovimientoRepository.findByObraId(obraId);
        double ejecutado = movimientosObra.stream()
                .filter(ComparadorPresupuestoService::esConsumoDeObra)
                .mapToDouble(m -> m.getCantidad() * m.getMaterial().getPrecioUnitario())
                .sum();

        double desviacionPct = presupuestado == 0
                ? 0
                : ((ejecutado - presupuestado) / presupuestado) * 100.0;

        double mermaRealVsEstimada = mermaRealVsEstimada(obraId);

        return new ReporteDesviacion(desviacionPct, mermaRealVsEstimada, presupuestado, ejecutado);
    }

    /**
     * Compara, material por material, la merma con que se cubicó
     * (cantidadConMerma vs cantidadCalculada de ItemCubicado) contra la
     * merma real (lo efectivamente despachado/consumido vs lo neto
     * cubicado), y devuelve el promedio de esa diferencia en toda la obra.
     */
    private double mermaRealVsEstimada(Long obraId) {
        List<Partida> partidas = partidaRepository.findByObraId(obraId);
        List<ItemCubicado> items = partidas.stream()
                .flatMap(p -> itemCubicadoRepository.findByPartidaId(p.getId()).stream())
                .toList();
        if (items.isEmpty()) {
            return 0;
        }

        double mermaEstimadaPromedio = items.stream()
                .filter(i -> i.getCantidadCalculada() > 0)
                .mapToDouble(i -> (i.getCantidadConMerma() / i.getCantidadCalculada() - 1) * 100.0)
                .average()
                .orElse(0);

        Map<Long, Double> netoCubicadoPorMaterial = items.stream()
                .collect(Collectors.groupingBy(
                        i -> i.getMaterial().getId(),
                        Collectors.summingDouble(ItemCubicado::getCantidadCalculada)));

        double mermaRealPromedio = netoCubicadoPorMaterial.entrySet().stream()
                .mapToDouble(e -> mermaRealDe(obraId, e.getKey(), e.getValue()))
                .average()
                .orElse(0);

        return mermaRealPromedio - mermaEstimadaPromedio;
    }

    private double mermaRealDe(Long obraId, Long materialId, double netoCubicado) {
        if (netoCubicado <= 0) {
            return 0;
        }
        double consumidoReal = kardexMovimientoRepository.findByObraIdAndMaterialId(obraId, materialId).stream()
                .filter(ComparadorPresupuestoService::esConsumoDeObra)
                .mapToDouble(KardexMovimiento::getCantidad)
                .sum();
        return ((consumidoReal - netoCubicado) / netoCubicado) * 100.0;
    }

    private static boolean esConsumoDeObra(KardexMovimiento m) {
        return m.getTipoMovimiento() == TipoMovimiento.DESPACHO || m.getTipoMovimiento() == TipoMovimiento.CONSUMO;
    }
}
