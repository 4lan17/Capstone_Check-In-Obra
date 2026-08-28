package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.UsuarioRepository;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.cubicacion.MaterialService;
import cl.duocuc.checkinobra.obra.Obra;
import cl.duocuc.checkinobra.obra.ObraService;
import cl.duocuc.checkinobra.obra.Trabajador;
import cl.duocuc.checkinobra.obra.TrabajadorService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.NoSuchElementException;

/**
 * Igual flujo que SolicitudHerramienta pero, al aprobar, genera un
 * KardexMovimiento de DESPACHO en vez de un préstamo
 * (SolicitudMaterial "1" -- "0..1" KardexMovimiento : genera >).
 */
@Service
@Transactional
public class SolicitudMaterialService {

    private final SolicitudMaterialRepository solicitudMaterialRepository;
    private final TrabajadorService trabajadorService;
    private final MaterialService materialService;
    private final ObraService obraService;
    private final UsuarioRepository usuarioRepository;
    private final KardexMovimientoService kardexMovimientoService;

    public SolicitudMaterialService(
            SolicitudMaterialRepository solicitudMaterialRepository,
            TrabajadorService trabajadorService,
            MaterialService materialService,
            ObraService obraService,
            UsuarioRepository usuarioRepository,
            KardexMovimientoService kardexMovimientoService) {
        this.solicitudMaterialRepository = solicitudMaterialRepository;
        this.trabajadorService = trabajadorService;
        this.materialService = materialService;
        this.obraService = obraService;
        this.usuarioRepository = usuarioRepository;
        this.kardexMovimientoService = kardexMovimientoService;
    }

    public SolicitudMaterial crear(Long trabajadorId, Long materialId, Long obraId, double cantidad) {
        Trabajador trabajador = trabajadorService.obtener(trabajadorId);
        Material material = materialService.obtener(materialId);
        Obra obra = obraService.obtener(obraId);

        SolicitudMaterial solicitud = SolicitudMaterial.builder()
                .trabajador(trabajador)
                .material(material)
                .obra(obra)
                .cantidad(cantidad)
                .estado(EstadoSolicitud.PENDIENTE)
                .fechaSolicitud(LocalDateTime.now())
                .build();
        return solicitudMaterialRepository.save(solicitud);
    }

    /**
     * SolicitudMaterial.aprobar(): KardexMovimiento del diagrama. Si la
     * cantidad pedida supera el stock, el bodeguero debe volver a llamar
     * con la cantidad efectivamente disponible (igual que en la pantalla
     * de despacho: no hay aprobación parcial automática).
     */
    public KardexMovimiento aprobar(Long solicitudId, Long aprobadorId, double cantidadAEntregar) {
        SolicitudMaterial solicitud = obtener(solicitudId);
        Usuario aprobador = usuarioRepository.findById(aprobadorId)
                .orElseThrow(() -> new NoSuchElementException("Usuario no encontrado: " + aprobadorId));

        solicitud.aprobar(aprobador);
        solicitudMaterialRepository.save(solicitud);

        return kardexMovimientoService.registrarMovimiento(
                solicitud.getObra().getId(),
                solicitud.getMaterial().getId(),
                aprobadorId,
                TipoMovimiento.DESPACHO,
                cantidadAEntregar);
    }

    /** SolicitudMaterial.rechazar() del diagrama. */
    public SolicitudMaterial rechazar(Long solicitudId, Long rechazadorId, String motivo) {
        SolicitudMaterial solicitud = obtener(solicitudId);
        Usuario rechazador = usuarioRepository.findById(rechazadorId)
                .orElseThrow(() -> new NoSuchElementException("Usuario no encontrado: " + rechazadorId));
        solicitud.rechazar(rechazador, motivo);
        return solicitudMaterialRepository.save(solicitud);
    }

    @Transactional(readOnly = true)
    public SolicitudMaterial obtener(Long id) {
        return solicitudMaterialRepository.findById(id)
                .orElseThrow(() -> new NoSuchElementException("Solicitud no encontrada: " + id));
    }

    @Transactional(readOnly = true)
    public List<SolicitudMaterial> listarPorTrabajador(Long trabajadorId) {
        return solicitudMaterialRepository.findByTrabajadorId(trabajadorId);
    }

    @Transactional(readOnly = true)
    public List<SolicitudMaterial> listarPorObra(Long obraId) {
        return solicitudMaterialRepository.findByObraId(obraId);
    }

    @Transactional(readOnly = true)
    public List<SolicitudMaterial> listarPendientesPorObra(Long obraId) {
        return solicitudMaterialRepository.findByObraIdAndEstado(obraId, EstadoSolicitud.PENDIENTE);
    }
}
