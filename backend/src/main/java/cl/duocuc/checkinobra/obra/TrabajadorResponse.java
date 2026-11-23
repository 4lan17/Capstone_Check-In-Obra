package cl.duocuc.checkinobra.obra;

/**
 * Lo que la API expone de un {@link Trabajador} en listados y consultas.
 *
 * <p><b>Sin {@code credencialQr} a propósito.</b> Ese UUID funcionaba como
 * portador: quien lo tenía podía presentarse en bodega como ese trabajador, y
 * listarlo equivalía a repartir las credenciales de la cuadrilla entera. Desde
 * SEG13 (S-27) no viaja en ninguna respuesta: la credencial es un código de vida
 * corta que el trabajador pide a su teléfono ({@link CodigoCredencialResponse}).
 */
public record TrabajadorResponse(
        Long id, String rut, Long usuarioId, String nombre, String rol, Long cuadrillaId) {

    public static TrabajadorResponse de(Trabajador t) {
        return new TrabajadorResponse(
                t.getId(),
                t.rut(),
                t.getUsuario().getId(),
                t.getUsuario().getNombre(),
                t.getUsuario().getRol().name(),
                t.getCuadrilla() == null ? null : t.getCuadrilla().getId());
    }
}
