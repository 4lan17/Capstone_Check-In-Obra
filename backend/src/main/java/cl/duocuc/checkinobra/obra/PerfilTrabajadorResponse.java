package cl.duocuc.checkinobra.obra;

/**
 * Lo que un trabajador ve de sí mismo: sus datos y dónde trabaja.
 *
 * <p>Sin {@code credencialQr} (SEG13, S-27): el QR fijo era un portador, y
 * quien lo fotografiaba se presentaba en bodega como ese trabajador. Lo que el
 * teléfono dibuja ahora es un código de vida corta que pide aparte
 * ({@code POST /api/trabajadores/yo/credencial/codigo}).
 *
 * <p>Cuadrilla y obra son nulas si todavía no lo asignan a ninguna.
 */
public record PerfilTrabajadorResponse(
        Long id,
        Long usuarioId,
        String nombre,
        String rut,
        Long cuadrillaId,
        String cuadrillaNombre,
        Long obraId,
        String obraNombre,
        String obraEstado) {

    public static PerfilTrabajadorResponse de(Trabajador t) {
        Cuadrilla c = t.getCuadrilla();
        Obra o = c == null ? null : c.getObra();
        return new PerfilTrabajadorResponse(
                t.getId(),
                t.getUsuario().getId(),
                t.nombre(),
                t.rut(),
                c == null ? null : c.getId(),
                c == null ? null : c.getNombre(),
                o == null ? null : o.getId(),
                o == null ? null : o.getNombre(),
                o == null ? null : o.getEstado().name());
    }
}
