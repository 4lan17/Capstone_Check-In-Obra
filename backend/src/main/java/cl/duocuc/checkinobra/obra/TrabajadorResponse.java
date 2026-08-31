package cl.duocuc.checkinobra.obra;

/**
 * Lo que la API expone de un {@link Trabajador} en listados y consultas.
 *
 * <p><b>Sin {@code credencialQr} a propósito.</b> Ese código es un UUID
 * aleatorio que funciona como portador: quien lo tiene puede presentarse en
 * bodega como ese trabajador. Listarlo equivale a repartir las credenciales de
 * la cuadrilla entera. Solo se devuelve al emitirlo o renovarlo, con
 * {@link TrabajadorCredencialResponse}.
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
