package cl.duocuc.checkinobra.config;

import java.util.List;

/**
 * Guardián del aislamiento entre empresas.
 *
 * <p>El rol decide <em>qué</em> puede hacer alguien; esto decide <em>sobre qué
 * datos</em>. Sin él, un bodeguero con un token válido lee el inventario de otra
 * constructora probando ids — el rol lo dejaba pasar porque el rol era correcto.
 *
 * <p>Es estático a propósito. La alternativa era un {@code @Component} inyectado
 * en los diecisiete servicios, y esa ceremonia hace más probable que alguien
 * omita la comprobación por no agregar otra dependencia al constructor. La
 * empresa de quien llama es contexto de la petición, igual que el usuario
 * autenticado, y se lee del mismo lugar.
 */
public final class AccesoEmpresa {

    private AccesoEmpresa() {
    }

    /**
     * ¿Este recurso es de la empresa de quien llama?
     *
     * <p>Está pensado para encadenarse sobre el {@code Optional} del repositorio:
     *
     * <pre>{@code
     * return obraRepository.findById(id)
     *         .filter(AccesoEmpresa::esPropio)
     *         .orElseThrow(() -> new NoSuchElementException("Obra no encontrada: " + id));
     * }</pre>
     *
     * <p>Filtrar en vez de lanzar es deliberado, y es la diferencia entre aislar
     * de verdad y solo aparentarlo. Si el recurso ajeno lanzara un 403 propio, la
     * respuesta distinguiría "existe pero no es tuyo" de "no existe", y esa
     * diferencia basta para recorrer los ids del sistema y saber cuántas obras
     * tiene la competencia. Convertido en {@code Optional} vacío, un recurso
     * ajeno produce exactamente el mismo 404, con el mismo mensaje, que uno que
     * nunca existió.
     */
    public static boolean esPropio(PerteneceAEmpresa recurso) {
        Long empresaId = recurso.empresaId();
        return empresaId != null && empresaId.equals(SesionActual.empresaId());
    }

    /** Filtra una lista dejando solo lo de la empresa de quien llama. */
    public static <T extends PerteneceAEmpresa> List<T> soloPropios(List<T> recursos) {
        return recursos.stream().filter(AccesoEmpresa::esPropio).toList();
    }

    /**
     * Comprueba un id de empresa suelto. Acá sí es 403 y no 404: no se está
     * pidiendo un recurso que pueda existir o no, se está afirmando pertenecer a
     * una empresa que no es la propia. No hay nada que enumerar.
     */
    public static void exigirEmpresa(Long empresaId) {
        if (empresaId == null || !empresaId.equals(SesionActual.empresaId())) {
            throw new AccesoDenegadoException("El recurso solicitado no pertenece a tu empresa");
        }
    }
}
