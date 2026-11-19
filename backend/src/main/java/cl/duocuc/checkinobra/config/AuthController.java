package cl.duocuc.checkinobra.config;

import jakarta.validation.Valid;
import com.fasterxml.jackson.annotation.JsonAlias;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * El diagrama modela Usuario.autenticar(pin) y Usuario.autenticarPorEmail(email)
 * como dos verificaciones separadas — Usuario solo guarda pinHash, no una
 * contraseña aparte. Por eso el login para los 4 roles queda unificado como
 * "correo + PIN": el correo ubica al usuario (autenticarPorEmail) y el PIN
 * lo autentica (autenticar). La app móvil, que ya conoce al usuario en el
 * teléfono, usa el segundo endpoint solo con el id + PIN.
 */
@RestController
@RequestMapping("/api/auth")
@Tag(name = "Autenticación")
public class AuthController {

    private final AutenticacionService autenticacionService;
    private final JwtService jwtService;

    public AuthController(AutenticacionService autenticacionService, JwtService jwtService) {
        this.autenticacionService = autenticacionService;
        this.jwtService = jwtService;
    }

    @PostMapping("/login")
    @Operation(summary = "Login por correo + clave — los cuatro roles. "
            + "ADMIN, JEFE_TERRENO y BODEGUERO usan una clave de 8 o más caracteres; TRABAJADOR, su PIN de 4 dígitos. "
            + "Responde 429 con Retry-After tras demasiados intentos fallidos.")
    public ResponseEntity<LoginResponse> login(@Valid @RequestBody LoginPorCorreoRequest req, HttpServletRequest http) {
        Usuario usuario = autenticacionService.loginPorCorreo(req.email(), req.pin(), http.getRemoteAddr());
        return ResponseEntity.ok(respuestaPara(usuario));
    }

    @PostMapping("/login-pin")
    @Operation(summary = "Login por PIN — usuario ya identificado en el teléfono. Solo rol TRABAJADOR. "
            + "Responde 429 con Retry-After tras demasiados intentos fallidos.")
    public ResponseEntity<LoginResponse> loginPin(@Valid @RequestBody LoginPorPinRequest req, HttpServletRequest http) {
        Usuario usuario = autenticacionService.loginPorPin(req.usuarioId(), req.pin(), http.getRemoteAddr());
        return ResponseEntity.ok(respuestaPara(usuario));
    }

    @PutMapping("/pin")
    @Operation(summary = "Cambia la clave propia. Es lo único que puede llamar una cuenta con clave provisoria "
            + "(debeCambiarClave). Devuelve una sesión nueva, ya sin la obligación.")
    public ResponseEntity<LoginResponse> cambiarPin(@Valid @RequestBody CambiarPinRequest req, HttpServletRequest http) {
        Usuario usuario = autenticacionService.cambiarPin(
                SesionActual.usuarioId(), req.pinActual(), req.pinNuevo(), http.getRemoteAddr());
        return ResponseEntity.ok(respuestaPara(usuario));
    }

    private LoginResponse respuestaPara(Usuario usuario) {
        return new LoginResponse(
                jwtService.emitir(usuario),
                usuario.getId(),
                usuario.getNombre(),
                usuario.getRol(),
                usuario.getEmpresa().getId(),
                usuario.isDebeCambiarPin());
    }

    public record CambiarPinRequest(
            @NotBlank @Size(max = 72) String pinActual, @NotBlank @Size(max = 72) String pinNuevo) {
    }

    /**
     * {@code pin} lleva el PIN de 4 dígitos del TRABAJADOR o la clave de 8 o más
     * caracteres de los demás roles; {@code clave} es un alias del mismo campo.
     */
    public record LoginPorCorreoRequest(
            @NotBlank String email,
            @NotBlank @Size(min = 4, max = 72) @JsonAlias("clave") String pin) {
    }

    public record LoginPorPinRequest(@NotNull Long usuarioId, @NotBlank @Pattern(regexp = "\\d{4}") String pin) {
    }

    /**
     * @param debeCambiarClave la clave es provisoria: el token solo sirve para
     *     {@code PUT /api/auth/pin} hasta que la cambie
     */
    public record LoginResponse(
            String token, Long usuarioId, String nombre, RolUsuario rol, Long empresaId, boolean debeCambiarClave) {
    }
}
