package cl.duocuc.checkinobra.obra;

import cl.duocuc.checkinobra.config.SesionActual;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.Valid;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/trabajadores")
@Tag(name = "Trabajador")
public class TrabajadorController {

    private final TrabajadorService trabajadorService;
    private final CodigoCredencialService codigoCredencialService;

    public TrabajadorController(
            TrabajadorService trabajadorService, CodigoCredencialService codigoCredencialService) {
        this.trabajadorService = trabajadorService;
        this.codigoCredencialService = codigoCredencialService;
    }

    @PostMapping
    @PreAuthorize("hasRole('ADMIN')")
    @ResponseStatus(HttpStatus.CREATED)
    public TrabajadorResponse crear(@Valid @RequestBody CrearTrabajadorRequest req) {
        // El RUT no viene acá: es del Usuario, y se define al registrarlo. La credencial no se
        // entrega: el trabajador pide su código de vida corta desde su propio teléfono.
        return TrabajadorResponse.de(trabajadorService.crear(req.usuarioId(), req.cuadrillaId()));
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasAnyRole('ADMIN', 'JEFE_TERRENO', 'BODEGUERO')")
    public TrabajadorResponse obtener(@PathVariable Long id) {
        return TrabajadorResponse.de(trabajadorService.obtener(id));
    }

    /**
     * Resuelve el código de credencial que el bodeguero acaba de escanear.
     *
     * <p>Solo acepta el código de vida corta (8 caracteres, ver {@link CodigoCredencialService}): el
     * UUID fijo de antes ya no sirve para escanear. Vencido es 409 {@code CREDENCIAL_CADUCADA};
     * desconocido, revocado o de otra empresa es 404.
     *
     * <p>Restringido a quien opera bodega: el código es portador (RN-27 de la especificación) mientras
     * dura, así que importa quién puede canjearlo. Quien escanea y acumula demasiados códigos
     * desconocidos queda bloqueado un rato (429).
     */
    @GetMapping("/por-credencial/{codigo}")
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO', 'JEFE_TERRENO')")
    public TrabajadorResponse buscarPorCredencial(@PathVariable String codigo) {
        return TrabajadorResponse.de(
                codigoCredencialService.canjear(codigo, SesionActual.empresaId(), SesionActual.usuarioId()));
    }

    /**
     * El listado trae nombre y RUT de toda una cuadrilla u obra: es de quien
     * opera la obra. Un trabajador no lo usa; ve lo suyo por {@code /yo}.
     */
    @GetMapping
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO', 'JEFE_TERRENO')")
    public List<TrabajadorResponse> listar(
            @RequestParam(required = false) Long cuadrillaId,
            @RequestParam(required = false) Long obraId) {
        if (cuadrillaId != null) {
            return trabajadorService.listarPorCuadrilla(cuadrillaId).stream()
                    .map(TrabajadorResponse::de)
                    .toList();
        }
        if (obraId != null) {
            return trabajadorService.listarPorObra(obraId).stream().map(TrabajadorResponse::de).toList();
        }
        throw new IllegalArgumentException("Se requiere cuadrillaId u obraId");
    }

    /** La ficha propia. Sale del token: no recibe id, así que no hay forma de pedir la de otro. */
    @GetMapping("/yo")
    @PreAuthorize("hasRole('TRABAJADOR')")
    public PerfilTrabajadorResponse yo() {
        return PerfilTrabajadorResponse.de(trabajadorService.miFicha());
    }

    /**
     * Emite un código de credencial de vida corta para quien llama (S-27). Sale del token y no recibe
     * id: no hay forma de pedir el de otro. Cada pedido emite uno nuevo; los anteriores valen hasta
     * que vencen. La respuesta lleva el código, así que IdempotenciaFilter no la guarda (S-30).
     */
    @PostMapping("/yo/credencial/codigo")
    @PreAuthorize("hasRole('TRABAJADOR')")
    public CodigoCredencialResponse pedirCodigoDeCredencial() {
        return codigoCredencialService.emitir(trabajadorService.obtenerPorUsuario(SesionActual.usuarioId()));
    }

    /** Renueva la propia: revoca todos los códigos vigentes del trabajador. */
    @PutMapping("/yo/credencial")
    @PreAuthorize("hasRole('TRABAJADOR')")
    public PerfilTrabajadorResponse renovarMiCredencial() {
        return PerfilTrabajadorResponse.de(trabajadorService.renovarMiCredencial());
    }

    /**
     * Renovar la credencial de cualquier trabajador es de ADMIN (si pierde el teléfono): revoca sus
     * códigos vigentes. No devuelve credenciales; el trabajador pide uno nuevo desde su teléfono.
     * El trabajador renueva la suya por {@code /yo/credencial}.
     */
    @PutMapping("/{id}/credencial")
    @PreAuthorize("hasRole('ADMIN')")
    public TrabajadorResponse renovarCredencial(@PathVariable Long id) {
        return TrabajadorResponse.de(trabajadorService.renovarCredencial(id));
    }

    public record CrearTrabajadorRequest(@NotNull(message = "Falta el usuario") Long usuarioId, Long cuadrillaId) {
    }
}
