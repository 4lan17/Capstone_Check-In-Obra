package cl.duocuc.checkinobra.config;

/**
 * Quien llama afirma pertenecer a una empresa que no es la suya, o no hay nadie
 * autenticado. Se traduce a 403.
 *
 * <p>No se usa para "pediste un recurso de otra empresa": ese caso devuelve el
 * mismo 404 que un id inexistente, porque distinguirlos permitiría enumerar los
 * ids del sistema. Ver {@link AccesoEmpresa#esPropio}.
 */
public class AccesoDenegadoException extends RuntimeException {

    public AccesoDenegadoException(String mensaje) {
        super(mensaje);
    }
}
