package cl.duocuc.checkinobra.config;

/**
 * Un {@link IllegalStateException} que además dice <b>cuál</b> conflicto es.
 *
 * <p>Sale como 409 igual que cualquier otro, pero lleva un {@code codigo} en el
 * cuerpo del error. La app lo necesita para decidir qué hacer sin leer el
 * mensaje: un 409 por stock insuficiente se le muestra al bodeguero y no se
 * reintenta, uno por una solicitud que ya se aprobó significa "ya estaba
 * hecho", y uno por dos escrituras que chocaron se puede reintentar.
 */
public class ConflictoException extends IllegalStateException {

    public static final String STOCK_INSUFICIENTE = "STOCK_INSUFICIENTE";
    public static final String YA_RESUELTA = "YA_RESUELTA";
    public static final String YA_DEVUELTO = "YA_DEVUELTO";
    public static final String OBRA_CERRADA = "OBRA_CERRADA";

    private final String codigo;

    public ConflictoException(String codigo, String mensaje) {
        super(mensaje);
        this.codigo = codigo;
    }

    public String codigo() {
        return codigo;
    }
}
