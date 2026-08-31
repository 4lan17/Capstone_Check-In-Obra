package cl.duocuc.checkinobra.config;

/** Lo que la API expone de una {@link Empresa}. */
public record EmpresaResponse(Long id, String nombre, String rut) {

    public static EmpresaResponse de(Empresa e) {
        return new EmpresaResponse(e.getId(), e.getNombre(), e.getRut());
    }
}
