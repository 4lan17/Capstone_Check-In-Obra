package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.AccesoEmpresa;
import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
import cl.duocuc.checkinobra.obra.Trabajador;
import cl.duocuc.checkinobra.obra.TrabajadorService;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.NoSuchElementException;

/**
 * El Trabajador crea la solicitud; el Bodeguero (o Admin) la aprueba desde
 * la cola — recién ahí se genera el PrestamoHerramienta (SolicitudHerramienta
 * "1" -- "0..1" PrestamoHerramienta : genera >).
 */
@Service
@Transactional
public class SolicitudHerramientaService {

    private final SolicitudHerramientaRepository solicitudHerramientaRepository;
    private final HerramientaRepository herramientaRepository;
    private final TrabajadorService trabajadorService;
    private final UsuarioRepository usuarioRepository;
    private final PrestamoHerramientaService prestamoHerramientaService;
    private final EntityManager entityManager;

    public SolicitudHerramientaService(
            SolicitudHerramientaRepository solicitudHerramientaRepository,
            HerramientaRepository herramientaRepository,
            TrabajadorService trabajadorService,
            UsuarioRepository usuarioRepository,
            PrestamoHerramientaService prestamoHerramientaService,
            EntityManager entityManager) {
        this.solicitudHerramientaRepository = solicitudHerramientaRepository;
        this.herramientaRepository = herramientaRepository;
        this.trabajadorService = trabajadorService;
        this.usuarioRepository = usuarioRepository;
        this.prestamoHerramientaService = prestamoHerramientaService;
        this.entityManager = entityManager;
    }

    /** @param usuarioId quien pide; el controlador lo saca del token */
    public SolicitudHerramienta crear(Long usuarioId, Long herramientaId, int cantidad) {
        Trabajador trabajador = trabajadorService.obtenerPorUsuario(usuarioId);
        Herramienta herramienta = herramientaRepository.findById(herramientaId)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Herramienta no encontrada: " + herramientaId));

        SolicitudHerramienta solicitud = SolicitudHerramienta.builder()
                .trabajador(trabajador)
                .herramienta(herramienta)
                .cantidad(cantidad)
                .estado(EstadoSolicitud.PENDIENTE)
                .fechaSolicitud(LocalDateTime.now())
                .build();
        return solicitudHerramientaRepository.save(solicitud);
    }

    /** SolicitudHerramienta.aprobar(): PrestamoHerramienta del diagrama. */
    public PrestamoHerramienta aprobar(Long solicitudId, Long aprobadorId, LocalDateTime fechaDevolEsperada) {
        SolicitudHerramienta solicitud = bloquear(solicitudId);
        Usuario aprobador = usuarioRepository.findById(aprobadorId)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Usuario no encontrado: " + aprobadorId));

        solicitud.aprobar(aprobador);
        solicitudHerramientaRepository.save(solicitud);

        Long obraId = solicitud.getTrabajador().getCuadrilla().getObra().getId();
        return prestamoHerramientaService.prestarDirecto(
                solicitud.getHerramienta().getId(),
                solicitud.getTrabajador().getId(),
                obraId,
                aprobadorId,
                fechaDevolEsperada);
    }

    /** SolicitudHerramienta.rechazar() del diagrama. */
    public SolicitudHerramienta rechazar(Long solicitudId, Long rechazadorId, String motivo) {
        SolicitudHerramienta solicitud = bloquear(solicitudId);
        Usuario rechazador = usuarioRepository.findById(rechazadorId)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Usuario no encontrado: " + rechazadorId));
        solicitud.rechazar(rechazador, motivo);
        return solicitudHerramientaRepository.save(solicitud);
    }

    /**
     * Dos aprobaciones simultáneas de la misma solicitud —un doble tap, o dos
     * bodegueros con la cola abierta— la veían PENDIENTE las dos y generaban
     * dos despachos. Con la fila bloqueada, la segunda espera y ve la solicitud
     * ya resuelta.
     */
    private SolicitudHerramienta bloquear(Long solicitudId) {
        var solicitud = obtener(solicitudId);
        entityManager.refresh(solicitud, LockModeType.PESSIMISTIC_WRITE);
        return solicitud;
    }

    @Transactional(readOnly = true)
    public SolicitudHerramienta obtener(Long id) {
        return solicitudHerramientaRepository.findById(id)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Solicitud no encontrada: " + id));
    }

    @Transactional(readOnly = true)
    public List<SolicitudHerramienta> listarPorTrabajador(Long trabajadorId) {
        trabajadorService.obtener(trabajadorId);
        return solicitudHerramientaRepository.findByTrabajadorId(trabajadorId);
    }

    @Transactional(readOnly = true)
    public List<SolicitudHerramienta> listarPorObra(Long obraId) {
        prestamoHerramientaService.listarPorObra(obraId);
        return solicitudHerramientaRepository.findByObraId(obraId);
    }

    @Transactional(readOnly = true)
    public List<SolicitudHerramienta> listarPendientesPorObra(Long obraId) {
        prestamoHerramientaService.listarPorObra(obraId);
        return solicitudHerramientaRepository.findByObraIdAndEstado(obraId, EstadoSolicitud.PENDIENTE);
    }
}
