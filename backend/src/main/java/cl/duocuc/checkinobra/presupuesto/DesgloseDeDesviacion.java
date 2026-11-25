package cl.duocuc.checkinobra.presupuesto;

import cl.duocuc.checkinobra.cubicacion.ItemCubicado;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.inventario.KardexMovimiento;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Function;

/**
 * Arma el desglose por material de la desviación: junta lo presupuestado (ítems del presupuesto),
 * lo ejecutado (despachos y consumos del kardex) y lo neto cubicado de la obra.
 *
 * <p>El ejecutado se valora al precio con que se presupuestó el material (el precio se copia al
 * agregar el ítem y no sigue al catálogo): así la desviación mide solo cuánto material se gastó de
 * más o de menos, no cuánto se movió el catálogo después. Un material que se consumió sin estar en
 * el presupuesto no tiene precio congelado: se valora al vigente del catálogo.
 */
public final class DesgloseDeDesviacion {

    private static final int DECIMALES = 2;

    private DesgloseDeDesviacion() {
    }

    /** Lo que se junta de cada material antes de convertirlo en fila. */
    private static final class Acumulado {
        private final Material material;
        private double cantidadPresupuestada;
        private double montoPresupuestado;
        private double cantidadEjecutada;
        private double netoCubicado;

        private Acumulado(Material material) {
            this.material = material;
        }

        private double precioDeValoracion() {
            return cantidadPresupuestada > 0
                    ? montoPresupuestado / cantidadPresupuestada
                    : material.getPrecioUnitario();
        }
    }

    static List<DesviacionMaterial> construir(
            List<PresupuestoItem> items,
            List<KardexMovimiento> consumos,
            List<ItemCubicado> cubicados,
            Function<Long, Double> mermaEstimadaDe,
            double umbralPct) {
        Map<Long, Acumulado> porMaterial = new LinkedHashMap<>();
        for (PresupuestoItem i : items) {
            Acumulado a = porMaterial.computeIfAbsent(i.getMaterial().getId(), k -> new Acumulado(i.getMaterial()));
            a.cantidadPresupuestada += i.getCantidad();
            a.montoPresupuestado += i.getSubtotal();
        }
        for (KardexMovimiento m : consumos) {
            porMaterial.computeIfAbsent(m.getMaterial().getId(), k -> new Acumulado(m.getMaterial()))
                    .cantidadEjecutada += m.getCantidad();
        }
        for (ItemCubicado c : cubicados) {
            Acumulado a = porMaterial.get(c.getMaterial().getId());
            if (a != null) {
                a.netoCubicado += c.getCantidadCalculada();
            }
        }
        return porMaterial.values().stream()
                .map(a -> fila(a, mermaEstimadaDe, umbralPct))
                .sorted(Comparator.comparingDouble((DesviacionMaterial f) -> Math.abs(f.desviacionMonto())).reversed()
                        .thenComparing(DesviacionMaterial::nombre))
                .toList();
    }

    private static DesviacionMaterial fila(Acumulado a, Function<Long, Double> mermaEstimadaDe, double umbralPct) {
        double montoEjecutado = a.cantidadEjecutada * a.precioDeValoracion();
        Double pct = porcentajeDeDesvio(a.montoPresupuestado, montoEjecutado);
        Double mermaReal = a.netoCubicado > 0 ? redondear((a.cantidadEjecutada / a.netoCubicado - 1) * 100.0) : null;
        return new DesviacionMaterial(
                a.material.getId(), a.material.getSku(), a.material.getNombre(), null,
                redondear(a.cantidadPresupuestada), redondear(a.cantidadEjecutada),
                redondear(a.montoPresupuestado), redondear(montoEjecutado),
                redondear(montoEjecutado - a.montoPresupuestado),
                pct, pct != null && pct > umbralPct,
                mermaEstimadaDe.apply(a.material.getId()), mermaReal);
    }

    /** (ejecutado − presupuestado) / presupuestado × 100, o nulo si no había presupuesto. */
    public static Double porcentajeDeDesvio(double presupuestado, double ejecutado) {
        return presupuestado == 0 ? null : redondear((ejecutado - presupuestado) / presupuestado * 100.0);
    }

    public static double redondear(double valor) {
        return BigDecimal.valueOf(valor).setScale(DECIMALES, RoundingMode.HALF_UP).doubleValue();
    }
}
