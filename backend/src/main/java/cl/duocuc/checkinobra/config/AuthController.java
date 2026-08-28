package cl.duocuc.checkinobra.config;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
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

    private final UsuarioRepository usuarioRepository;
    private final JwtService jwtService;

    public AuthController(UsuarioRepository usuarioRepository, JwtService jwtService) {
        this.usuarioRepository = usuarioRepository;
        this.jwtService = jwtService;
    }

    @PostMapping("/login")
    @Operation(summary = "Login por correo + PIN — admin, jefe de terreno y bodeguero")
    public ResponseEntity<LoginResponse> login(@RequestBody LoginPorCorreoRequest req) {
        Usuario usuario = usuarioRepository.findByEmail(req.email())
                .filter(u -> u.autenticarPorEmail(req.email()))
                .orElseThrow(() -> new IllegalArgumentException("Credenciales inválidas"));
        if (!usuario.autenticar(req.pin())) {
            throw new IllegalArgumentException("Credenciales inválidas");
        }
        return ResponseEntity.ok(respuestaPara(usuario));
    }

    @PostMapping("/login-pin")
    @Operation(summary = "Login por PIN — usuario ya identificado en el teléfono (rol TRABAJADOR)")
    public ResponseEntity<LoginResponse> loginPin(@RequestBody LoginPorPinRequest req) {
        Usuario usuario = usuarioRepository.findById(req.usuarioId())
                .orElseThrow(() -> new IllegalArgumentException("Credenciales inválidas"));
        if (!usuario.autenticar(req.pin())) {
            throw new IllegalArgumentException("Credenciales inválidas");
        }
        return ResponseEntity.ok(respuestaPara(usuario));
    }

    private LoginResponse respuestaPara(Usuario usuario) {
        return new LoginResponse(
                jwtService.emitir(usuario),
                usuario.getId(),
                usuario.getNombre(),
                usuario.getRol(),
                usuario.getEmpresa().getId());
    }

    public record LoginPorCorreoRequest(@NotBlank String email, @NotBlank @Pattern(regexp = "\\d{4}") String pin) {
    }

    public record LoginPorPinRequest(@NotNull Long usuarioId, @NotBlank @Pattern(regexp = "\\d{4}") String pin) {
    }

    public record LoginResponse(String token, Long usuarioId, String nombre, RolUsuario rol, Long empresaId) {
    }
}
