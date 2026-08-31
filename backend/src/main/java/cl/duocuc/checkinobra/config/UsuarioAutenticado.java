package cl.duocuc.checkinobra.config;

/**
 * Quién viene en el token, ya validado. Es el {@code principal} que queda en el
 * SecurityContext, y la única fuente confiable de "a qué empresa pertenece quien
 * está llamando".
 *
 * <p>La distinción importa: el {@code empresaId} que llega en un query param o
 * en el cuerpo de una petición lo escribe el cliente y puede ser cualquiera. El
 * de acá viene firmado.
 */
public record UsuarioAutenticado(Long usuarioId, String email, RolUsuario rol, Long empresaId) {
}
