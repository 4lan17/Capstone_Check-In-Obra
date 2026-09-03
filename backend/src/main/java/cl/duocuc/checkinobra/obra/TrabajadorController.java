package cl.duocuc.checkinobra.obra;

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

    public TrabajadorController(TrabajadorService trabajadorService) {
        this.trabajadorService = trabajadorService;
    }

    @PostMapping
    @PreAuthorize("hasRole('ADMIN')")
    @ResponseStatus(HttpStatus.CREATED)
    public TrabajadorCredencialResponse crear(@RequestBody CrearTrabajadorRequest req) {
        // Al crearlo se emite su credencial, y es la única vez que hay que
        // entregarla junto con el resto de los datos. El RUT no viene acá: es
        // del Usuario, y se define al registrarlo.
        return TrabajadorCredencialResponse.de(
                trabajadorService.crear(req.usuarioId(), req.cuadrillaId()));
    }

    @GetMapping("/{id}")
    public TrabajadorResponse obtener(@PathVariable Long id) {
        return TrabajadorResponse.de(trabajadorService.obtener(id));
    }

    /**
     * Resuelve la credencial que el bodeguero acaba de escanear.
     *
     * <p>Restringido a quien opera bodega. Antes lo podía llamar cualquier
     * usuario autenticado, y desde que escanear la credencial es el paso previo
     * a aprobar solicitudes, eso deja a un trabajador resolviendo el código de
     * un compañero desde su propio teléfono. El código es portador (RN-27 de la
     * especificación): quien lo tiene se presenta como ese trabajador, así que
     * importa quién puede canjearlo.
     */
    @GetMapping("/por-credencial/{credencialQr}")
    @PreAuthorize("hasAnyRole('ADMIN', 'BODEGUERO', 'JEFE_TERRENO')")
    public TrabajadorResponse buscarPorCredencial(@PathVariable String credencialQr) {
        // Quien escanea ya tiene el código en la mano: devolverlo otra vez solo
        // ampliaría por dónde puede filtrarse.
        return TrabajadorResponse.de(trabajadorService.buscarPorCredencialQr(credencialQr));
    }

    @GetMapping
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

    @PutMapping("/{id}/credencial")
    public TrabajadorCredencialResponse renovarCredencial(@PathVariable Long id) {
        // Renovar sin devolver el código nuevo dejaría al trabajador sin
        // credencial: acá sí tiene que viajar.
        return TrabajadorCredencialResponse.de(trabajadorService.renovarCredencial(id));
    }

    public record CrearTrabajadorRequest(Long usuarioId, Long cuadrillaId) {
    }
}
