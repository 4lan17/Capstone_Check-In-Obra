package cl.duocuc.checkinobra.control;

import java.time.LocalDateTime;

/** Lo que la API expone de una {@link Alerta}. */
public record AlertaResponse(
        Long id,
        String tipo,
        String mensaje,
        LocalDateTime fecha,
        boolean resuelto,
        Long obraId,
        Long prestamoHerramientaId) {

    public static AlertaResponse de(Alerta a) {
        return new AlertaResponse(
                a.getId(),
                a.getTipo().name(),
                a.getMensaje(),
                a.getFecha(),
                a.isResuelto(),
                a.getObra().getId(),
                // Solo las alertas de herramienta no devuelta apuntan a un préstamo.
                a.getPrestamoHerramienta() == null ? null : a.getPrestamoHerramienta().getId());
    }
}
