package cl.duocuc.checkinobra.cubicacion;

/** Lo que la API expone de un {@link Material}. */
public record MaterialResponse(
        Long id,
        String sku,
        String codigoBarra,
        String nombre,
        String categoria,
        double precioUnitario,
        double stockMinimo,
        Long empresaId) {

    public static MaterialResponse de(Material m) {
        return new MaterialResponse(
                m.getId(),
                m.getSku(),
                m.getCodigoBarra(),
                m.getNombre(),
                m.getCategoria().name(),
                m.getPrecioUnitario(),
                m.getStockMinimo(),
                m.getEmpresa().getId());
    }
}
