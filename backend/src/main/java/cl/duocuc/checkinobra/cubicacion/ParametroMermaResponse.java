package cl.duocuc.checkinobra.cubicacion;

/** Lo que la API expone de un {@link ParametroMerma}. */
public record ParametroMermaResponse(Long id, double porcentaje, Long materialId, String materialSku) {

    public static ParametroMermaResponse de(ParametroMerma p) {
        return new ParametroMermaResponse(
                p.getId(), p.getPorcentaje(), p.getMaterial().getId(), p.getMaterial().getSku());
    }
}
