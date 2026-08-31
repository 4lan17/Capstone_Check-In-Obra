package cl.duocuc.checkinobra.obra;

/** Lo que la API expone de una {@link Cuadrilla}. */
public record CuadrillaResponse(Long id, String nombre, Long obraId, String obraNombre) {

    public static CuadrillaResponse de(Cuadrilla c) {
        return new CuadrillaResponse(
                c.getId(), c.getNombre(), c.getObra().getId(), c.getObra().getNombre());
    }
}
