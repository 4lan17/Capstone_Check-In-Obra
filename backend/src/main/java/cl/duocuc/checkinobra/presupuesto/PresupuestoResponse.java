package cl.duocuc.checkinobra.presupuesto;

import java.time.LocalDate;

/** Lo que la API expone de un {@link Presupuesto}. */
public record PresupuestoResponse(
        Long id, String estado, LocalDate fechaCongelado, double total, Long obraId, String obraNombre) {

    public static PresupuestoResponse de(Presupuesto p) {
        return new PresupuestoResponse(
                p.getId(),
                p.getEstado().name(),
                p.getFechaCongelado(),
                p.getTotal(),
                p.getObra().getId(),
                p.getObra().getNombre());
    }
}
