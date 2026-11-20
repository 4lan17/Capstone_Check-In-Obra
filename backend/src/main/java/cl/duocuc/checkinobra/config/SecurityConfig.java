package cl.duocuc.checkinobra.config;

import jakarta.servlet.DispatcherType;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.HttpStatusEntryPoint;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    private final JwtService jwtService;
    private final ResolutorDeBases resolutor;
    private final ValidadorDeSesion validador;
    private final EventosDeSeguridad eventos;

    public SecurityConfig(
            JwtService jwtService, ResolutorDeBases resolutor, ValidadorDeSesion validador, EventosDeSeguridad eventos) {
        this.jwtService = jwtService;
        this.resolutor = resolutor;
        this.validador = validador;
        this.eventos = eventos;
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
                .csrf(AbstractHttpConfigurer::disable)
                .sessionManagement(sm -> sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                // Sin token, o con uno vencido o mal firmado → 401. El valor por
                // defecto de Spring Security para una API sin login por
                // formulario era 403, igual que un rol insuficiente, y la app no
                // podía distinguir "vuelve a entrar con tu PIN" de "tu rol no
                // permite esto". El 403 queda solo para lo segundo.
                .exceptionHandling(e -> e
                        .authenticationEntryPoint(new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED))
                        // Un rol que no alcanza (@PreAuthorize) sigue siendo 403, y ahora queda registrado.
                        .accessDeniedHandler((request, response, denegado) -> {
                            eventos.accesoDenegado(request.getMethod(), request.getRequestURI());
                            response.sendError(HttpStatus.FORBIDDEN.value());
                        }))
                .authorizeHttpRequests(auth -> auth
                        // Cuando algo falla, Spring reenvía internamente a
                        // /error. Ese reenvío pasa otra vez por esta cadena y,
                        // al no estar permitido, terminaba en un 403 con cuerpo
                        // vacío: un 404 o un 405 se veían como "no tienes
                        // permiso". Se permite el *dispatch* de error, no una
                        // petición directa a /error.
                        .dispatcherTypeMatchers(DispatcherType.ERROR).permitAll()
                        // Cambiar la propia clave exige estar autenticado: va antes
                        // del permitAll de /api/auth/**.
                        .requestMatchers(HttpMethod.PUT, "/api/auth/pin").authenticated()
                        .requestMatchers(
                                "/api/auth/**",
                                "/v3/api-docs/**",
                                "/swagger-ui/**",
                                "/swagger-ui.html")
                        .permitAll()
                        .anyRequest().authenticated())
                .addFilterBefore(new JwtAuthFilter(jwtService, resolutor, validador), UsernamePasswordAuthenticationFilter.class);
        return http.build();
    }
}
