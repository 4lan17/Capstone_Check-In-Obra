package cl.duocuc.checkinobra.config;

/**
 * Lo que la API expone de un {@link Usuario}.
 *
 * <p>Sin {@code pinHash} — no por una anotación que alguien pueda borrar sin
 * darse cuenta, sino porque el campo no existe en este record. La empresa se
 * aplana a su id y su nombre: quien pide un usuario no necesita el objeto
 * Empresa entero, y devolverlo abre otro grafo que mantener.
 */
public record UsuarioResponse(
        Long id,
        String nombre,
        String email,
        String rut,
        String rol,
        Long empresaId,
        String empresaNombre) {

    public static UsuarioResponse de(Usuario u) {
        return new UsuarioResponse(
                u.getId(),
                u.getNombre(),
                u.getEmail(),
                u.getRut(),
                u.getRol().name(),
                u.getEmpresa().getId(),
                u.getEmpresa().getNombre());
    }
}
