package cl.duocuc.checkinobra.config;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.jspecify.annotations.NonNull;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;

/** Lee el Bearer token de cada request y, si es válido, autentica al usuario. */
public class JwtAuthFilter extends OncePerRequestFilter {

    private final JwtService jwtService;

    public JwtAuthFilter(JwtService jwtService) {
        this.jwtService = jwtService;
    }

    /** La única llamada que una cuenta con clave provisoria puede hacer. */
    static final String RUTA_CAMBIO_DE_CLAVE = "/api/auth/pin";

    private static boolean esCambioDeClave(HttpServletRequest request) {
        return "PUT".equals(request.getMethod()) && RUTA_CAMBIO_DE_CLAVE.equals(request.getRequestURI());
    }

    /** Mismo cuerpo que {@code ApiExceptionHandler.ErrorBody}: la app lo lee igual. */
    private static void responderDebeCambiarPin(HttpServletResponse response) throws IOException {
        response.setStatus(HttpServletResponse.SC_FORBIDDEN);
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        response.getWriter().write("{\"instante\":\"" + java.time.Instant.now() + "\",\"status\":403,"
                + "\"mensaje\":\"Debes cambiar tu clave antes de seguir usando la aplicación\","
                + "\"codigo\":\"" + DEBE_CAMBIAR_PIN + "\"}");
    }

    /** Valor de {@code codigo} cuando la cuenta debe cambiar su clave primero. */
    public static final String DEBE_CAMBIAR_PIN = "DEBE_CAMBIAR_PIN";

    @Override
    protected void doFilterInternal(
            @NonNull HttpServletRequest request,
            @NonNull HttpServletResponse response,
            @NonNull FilterChain filterChain) throws ServletException, IOException {

        String header = request.getHeader("Authorization");
        if (header != null && header.startsWith("Bearer ")) {
            try {
                Claims claims = jwtService.validarYExtraer(header.substring(7));
                // Cuenta con clave provisoria: solo puede cambiarla. Se corta acá y
                // no por @PreAuthorize: hay endpoints sin rol (solo autenticados) y
                // quedarían abiertos.
                if (Boolean.TRUE.equals(claims.get("cambiarPin", Boolean.class)) && !esCambioDeClave(request)) {
                    SecurityContextHolder.clearContext();
                    responderDebeCambiarPin(response);
                    return;
                }
                String rol = claims.get("rol", String.class);
                // El principal es el usuario completo, no solo su id: el
                // empresaId viaja firmado en el token y es lo que después
                // decide a qué datos puede llegar esta petición.
                var usuario = new UsuarioAutenticado(
                        Long.valueOf(claims.getSubject()),
                        claims.get("email", String.class),
                        RolUsuario.valueOf(rol),
                        claims.get("empresaId", Number.class).longValue());
                var authToken = new UsernamePasswordAuthenticationToken(
                        usuario,
                        null,
                        List.of(new SimpleGrantedAuthority("ROLE_" + rol)));
                SecurityContextHolder.getContext().setAuthentication(authToken);
            } catch (JwtException | IllegalArgumentException ex) {
                SecurityContextHolder.clearContext();
            }
        }
        filterChain.doFilter(request, response);
    }
}
