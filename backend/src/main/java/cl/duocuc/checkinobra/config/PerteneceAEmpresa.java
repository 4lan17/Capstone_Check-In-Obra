package cl.duocuc.checkinobra.config;

/**
 * Todo dato del sistema es de alguna empresa. Esta interfaz obliga a cada
 * entidad a saber decir de cuál, recorriendo su propia cadena de relaciones
 * ({@code Cuadrilla → Obra → Empresa}, {@code SolicitudHerramienta → Trabajador
 * → Usuario → Empresa}).
 *
 * <p>Que la respuesta la dé la entidad y no el servicio es lo que permite un
 * único guardián ({@link AccesoEmpresa}) en vez de una comprobación distinta por
 * cada caso, y lo que permite verificar por reflexión que ninguna entidad quedó
 * fuera.
 */
public interface PerteneceAEmpresa {

    /** Id de la empresa dueña de este dato. */
    Long empresaId();
}
