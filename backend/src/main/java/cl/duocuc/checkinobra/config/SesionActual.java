package cl.duocuc.checkinobra.config;

import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

/** Acceso al {@link UsuarioAutenticado} de la petición en curso. */
public final class SesionActual {

    private SesionActual() {
    }

    /**
     * @throws AccesoDenegadoException si no hay nadie autenticado. Que llegue acá
     *     una petición anónima significa que alguien agregó una ruta pública que
     *     igual consulta datos de empresa: mejor que falle a que devuelva algo.
     */
    public static UsuarioAutenticado usuario() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !(auth.getPrincipal() instanceof UsuarioAutenticado usuario)) {
            throw new AccesoDenegadoException("No hay un usuario autenticado en esta petición");
        }
        return usuario;
    }

    public static Long empresaId() {
        return usuario().empresaId();
    }

    public static Long usuarioId() {
        return usuario().usuarioId();
    }
}
