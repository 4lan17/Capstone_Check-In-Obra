package cl.duocuc.checkinobra.plataforma;

import cl.duocuc.checkinobra.config.CatalogoDeEmpresas;
import cl.duocuc.checkinobra.config.CatalogoDeEmpresas.EmpresaRegistrada;
import cl.duocuc.checkinobra.config.CatalogoDeEmpresas.OperadorRegistrado;
import cl.duocuc.checkinobra.config.JwtService;
import cl.duocuc.checkinobra.config.SesionActual;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * Las rutas del operador de plataforma (MT6, #109). Solo las toca el rol {@code PLATAFORMA}
 * (ver {@code SecurityConfig}), que no pertenece a ninguna empresa: nada de lo que hay acá abre la
 * base de una.
 */
@RestController
@RequestMapping("/api/plataforma")
@Tag(name = "Plataforma")
public class PlataformaController {

    private final PlataformaAutenticacionService autenticacion;
    private final CatalogoDeEmpresas catalogo;
    private final JwtService jwtService;

    public PlataformaController(
            PlataformaAutenticacionService autenticacion, CatalogoDeEmpresas catalogo, JwtService jwtService) {
        this.autenticacion = autenticacion;
        this.catalogo = catalogo;
        this.jwtService = jwtService;
    }

    @PostMapping("/auth/login")
    public SesionDePlataformaResponse login(@Valid @RequestBody LoginDeOperadorRequest req, HttpServletRequest http) {
        OperadorRegistrado operador = autenticacion.login(req.email(), req.clave(), http.getRemoteAddr());
        return new SesionDePlataformaResponse(jwtService.emitirParaOperador(operador), operador.email(), operador.nombre());
    }

    @GetMapping("/yo")
    public OperadorResponse yo() {
        return catalogo.buscarOperadorActivo(SesionActual.usuario().usuarioId())
                .map(o -> new OperadorResponse(o.id(), o.email(), o.nombre()))
                .orElseThrow();
    }

    /** Las empresas registradas, sin lo que sirve para abrir su base (usuario de base y secreto). */
    @GetMapping("/empresas")
    public List<EmpresaDePlataformaResponse> empresas() {
        return catalogo.listar().stream().map(EmpresaDePlataformaResponse::de).toList();
    }

    public record LoginDeOperadorRequest(
            @NotBlank @Size(max = 255) String email, @NotBlank @Size(max = 200) String clave) {
    }

    public record SesionDePlataformaResponse(String token, String email, String nombre) {
    }

    public record OperadorResponse(Long id, String email, String nombre) {
    }

    public record EmpresaDePlataformaResponse(
            Long id, String rut, String nombre, String plan, String estado, String migracionEstado) {

        static EmpresaDePlataformaResponse de(EmpresaRegistrada e) {
            return new EmpresaDePlataformaResponse(
                    e.id(), e.rut(), e.nombre(), e.plan(), e.estado(), e.migracionEstado());
        }
    }
}
