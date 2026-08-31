package cl.duocuc.checkinobra.cubicacion;

/** Lo que la API expone de una {@link Partida}. */
public record PartidaResponse(
        Long id,
        String tipo,
        double anchoM,
        double altoM,
        double separacionMontantes,
        Long obraId) {

    public static PartidaResponse de(Partida p) {
        return new PartidaResponse(
                p.getId(),
                p.getTipo().name(),
                p.getAnchoM(),
                p.getAltoM(),
                p.getSeparacionMontantes(),
                p.getObra().getId());
    }
}
