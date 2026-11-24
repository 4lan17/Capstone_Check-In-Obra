package cl.duocuc.checkinobra.obra;

/** Lo que la API expone de una {@link Obra}. */
public record ObraResponse(
        Long id,
        String nombre,
        String cliente,
        String ubicacion,
        String estado,
        Long empresaId,
        Long jefeTerrenoId,
        String jefeTerrenoNombre,
        String jefeTerrenoRut,
        Double latitud,
        Double longitud) {

    public static ObraResponse de(Obra o) {
        // Nulos mientras la obra no tenga jefe asignado. Se mandan los tres
        // campos igual, para que el cliente distinga "sin jefe" de "no vino el
        // dato".
        boolean tieneJefe = o.getJefeTerreno() != null;
        return new ObraResponse(
                o.getId(),
                o.getNombre(),
                o.getCliente(),
                o.getUbicacion(),
                o.getEstado().name(),
                o.getEmpresa().getId(),
                tieneJefe ? o.getJefeTerreno().getId() : null,
                tieneJefe ? o.getJefeTerreno().getNombre() : null,
                tieneJefe ? o.getJefeTerreno().getRut() : null,
                // Nulos: obra sin ubicación en el mapa (el texto `ubicacion` va aparte).
                o.getLatitud() == null ? null : o.getLatitud().doubleValue(),
                o.getLongitud() == null ? null : o.getLongitud().doubleValue());
    }
}
