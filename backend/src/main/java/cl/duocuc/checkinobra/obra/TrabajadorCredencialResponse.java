package cl.duocuc.checkinobra.obra;

/**
 * El trabajador <b>con</b> su credencial QR. Se devuelve solo en los dos
 * momentos en que el código tiene que llegar a alguien: cuando se emite y
 * cuando se renueva. Para todo lo demás está {@link TrabajadorResponse}.
 */
public record TrabajadorCredencialResponse(
        Long id, String rut, Long usuarioId, String nombre, Long cuadrillaId, String credencialQr) {

    public static TrabajadorCredencialResponse de(Trabajador t) {
        return new TrabajadorCredencialResponse(
                t.getId(),
                t.rut(),
                t.getUsuario().getId(),
                t.getUsuario().getNombre(),
                t.getCuadrilla() == null ? null : t.getCuadrilla().getId(),
                t.getCredencialQr());
    }
}
