package cl.duocuc.checkinobra.presupuesto;

import cl.duocuc.checkinobra.cubicacion.ItemCubicado;
import cl.duocuc.checkinobra.cubicacion.ItemCubicadoRepository;
import cl.duocuc.checkinobra.cubicacion.ParametroMerma;
import cl.duocuc.checkinobra.cubicacion.ParametroMermaRepository;
import cl.duocuc.checkinobra.cubicacion.PartidaRepository;
import cl.duocuc.checkinobra.inventario.KardexMovimiento;
import cl.duocuc.checkinobra.inventario.KardexMovimientoRepository;
import cl.duocuc.checkinobra.inventario.TipoMovimiento;
import org.springframework.beans.factory.annotation.Value;
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
    private final PresupuestoItemRepository presupuestoItemRepository;
    private final ParametroMermaRepository parametroMermaRepository;
    private final double umbralPct;

    public ComparadorPresupuestoService(
            KardexMovimientoRepository kardexMovimientoRepository,
            PartidaRepository partidaRepository,
            ItemCubicadoRepository itemCubicadoRepository,
            PresupuestoItemRepository presupuestoItemRepository,
            ParametroMermaRepository parametroMermaRepository,
            @Value("${checkinobra.presupuesto.umbral-desviacion-pct:10}") double umbralPct) {
        this.kardexMovimientoRepository = kardexMovimientoRepository;
        this.partidaRepository = partidaRepository;
        this.itemCubicadoRepository = itemCubicadoRepository;
        this.presupuestoItemRepository = presupuestoItemRepository;
        this.parametroMermaRepository = parametroMermaRepository;
        this.umbralPct = umbralPct;
    }

    public ReporteDesviacion compararVsEjecutado(Presupuesto presupuesto) {
        Long obraId = presupuesto.getObra().getId();
        double presupuestado = presupuesto.getTotal();

        List<KardexMovimiento> consumos = kardexMovimientoRepository.findByObraId(obraId).stream()
                .filter(ComparadorPresupuestoService::esConsumoDeObra)
                .toList();
        List<ItemCubicado> cubicados = itemsCubicadosDeLaObra(obraId);

        List<DesviacionMaterial> materiales = DesgloseDeDesviacion.construir(
                presupuestoItemRepository.findByPresupuestoId(presupuesto.getId()),
                consumos, cubicados, this::mermaEstimadaDe, umbralPct);
        double ejecutado = DesgloseDeDesviacion.redondear(
                materiales.stream().mapToDouble(DesviacionMaterial::montoEjecutado).sum());

        Double pct = DesgloseDeDesviacion.porcentajeDeDesvio(presupuestado, ejecutado);
        double desviacionPct = pct == null ? 0 : pct;

        return new ReporteDesviacion(
                desviacionPct, mermaRealVsEstimada(obraId, cubicados), presupuestado, ejecutado,
                DesgloseDeDesviacion.redondear(ejecutado - presupuestado),
                umbralPct, desviacionPct > umbralPct, materiales);
    }

    /** Merma parametrizada del catálogo para el material, o nulo si no tiene parámetro. */
    private Double mermaEstimadaDe(Long materialId) {
        return parametroMermaRepository.findByMaterialId(materialId).map(ParametroMerma::getPorcentaje).orElse(null);
    }

    private List<ItemCubicado> itemsCubicadosDeLaObra(Long obraId) {
        return partidaRepository.findByObraId(obraId).stream()
                .flatMap(p -> itemCubicadoRepository.findByPartidaId(p.getId()).stream())
                .toList();
    }

    /**
     * Compara, material por material, la merma con que se cubicó
     * (cantidadConMerma vs cantidadCalculada de ItemCubicado) contra la
     * merma real (lo efectivamente despachado/consumido vs lo neto
     * cubicado), y devuelve el promedio de esa diferencia en toda la obra.
     */
    private double mermaRealVsEstimada(Long obraId, List<ItemCubicado> items) {
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
