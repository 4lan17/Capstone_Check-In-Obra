package cl.duocuc.checkinobra.presupuesto;

/** Lo que la API expone de un {@link PresupuestoItem}. */
public record PresupuestoItemResponse(
        Long id,
        double cantidad,
        double precioUnitario,
        double subtotal,
        Long presupuestoId,
        Long materialId,
        String materialSku,
        String materialNombre) {

    public static PresupuestoItemResponse de(PresupuestoItem i) {
        return new PresupuestoItemResponse(
                i.getId(),
                i.getCantidad(),
                i.getPrecioUnitario(),
                i.getSubtotal(),
                i.getPresupuesto().getId(),
                i.getMaterial().getId(),
                i.getMaterial().getSku(),
                i.getMaterial().getNombre());
    }
}
