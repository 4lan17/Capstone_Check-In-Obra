package cl.duocuc.checkinobra.cubicacion;

/**
 * Lo que la API expone de un {@link ItemCubicado}. Lleva el SKU y el nombre del
 * material porque el resultado de cubicar se lee como una lista de materiales;
 * sin ellos la app tendría que pedir cada material por separado.
 */
public record ItemCubicadoResponse(
        Long id,
        double cantidadCalculada,
        double cantidadConMerma,
        Long partidaId,
        Long materialId,
        String materialSku,
        String materialNombre) {

    public static ItemCubicadoResponse de(ItemCubicado i) {
        return new ItemCubicadoResponse(
                i.getId(),
                i.getCantidadCalculada(),
                i.getCantidadConMerma(),
                i.getPartida().getId(),
                i.getMaterial().getId(),
                i.getMaterial().getSku(),
                i.getMaterial().getNombre());
    }
}
