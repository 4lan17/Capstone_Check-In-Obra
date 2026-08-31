package cl.duocuc.checkinobra.inventario;

import java.time.LocalDateTime;

/** Lo que la API expone de un {@link PrestamoHerramienta}. */
public record PrestamoHerramientaResponse(
        Long id,
        LocalDateTime fechaPrestamo,
        LocalDateTime fechaDevolEsperada,
        LocalDateTime fechaDevolReal,
        Long herramientaId,
        String herramientaNombre,
        String herramientaEstado,
        Long trabajadorId,
        String trabajadorNombre,
        String trabajadorRut,
        Long obraId,
        Long autorizadoPorId,
        String autorizadoPorNombre) {

    public static PrestamoHerramientaResponse de(PrestamoHerramienta p) {
        return new PrestamoHerramientaResponse(
                p.getId(),
                p.getFechaPrestamo(),
                p.getFechaDevolEsperada(),
                // Nula mientras la herramienta siga afuera.
                p.getFechaDevolReal(),
                p.getHerramienta().getId(),
                p.getHerramienta().getNombre(),
                p.getHerramienta().getEstado().name(),
                p.getTrabajador().getId(),
                p.getTrabajador().nombre(),
                p.getTrabajador().rut(),
                p.getObra().getId(),
                p.getAutorizadoPor().getId(),
                p.getAutorizadoPor().getNombre());
    }
}
