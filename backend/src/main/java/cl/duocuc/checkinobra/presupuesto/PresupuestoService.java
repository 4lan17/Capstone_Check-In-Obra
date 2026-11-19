package cl.duocuc.checkinobra.presupuesto;

import cl.duocuc.checkinobra.config.AccesoEmpresa;
import cl.duocuc.checkinobra.cubicacion.Material;
import cl.duocuc.checkinobra.cubicacion.MaterialService;
import cl.duocuc.checkinobra.obra.Obra;
import cl.duocuc.checkinobra.obra.ObraService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.NoSuchElementException;

@Service
@Transactional
public class PresupuestoService {

    private final PresupuestoRepository presupuestoRepository;
    private final PresupuestoItemRepository presupuestoItemRepository;
    private final ObraService obraService;
    private final MaterialService materialService;

    public PresupuestoService(
            PresupuestoRepository presupuestoRepository,
            PresupuestoItemRepository presupuestoItemRepository,
            ObraService obraService,
            MaterialService materialService) {
        this.presupuestoRepository = presupuestoRepository;
        this.presupuestoItemRepository = presupuestoItemRepository;
        this.obraService = obraService;
        this.materialService = materialService;
    }

    public Presupuesto crear(Long obraId) {
        // Primero la obra: si es ajena responde el mismo 404 que una inexistente.
        // Preguntar antes por el presupuesto delataba qué obras de otra empresa
        // ya tienen uno (409 frente a 404).
        Obra obra = obraService.obtener(obraId);
        if (presupuestoRepository.findByObraId(obraId).isPresent()) {
            throw new IllegalStateException("La obra ya tiene un presupuesto");
        }
        Presupuesto presupuesto = Presupuesto.builder()
                .estado(EstadoPresupuesto.BORRADOR)
                .total(0)
                .obra(obra)
                .build();
        return presupuestoRepository.save(presupuesto);
    }

    @Transactional(readOnly = true)
    public Presupuesto obtener(Long id) {
        return presupuestoRepository.findById(id)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Presupuesto no encontrado: " + id));
    }

    @Transactional(readOnly = true)
    public Presupuesto obtenerPorObra(Long obraId) {
        obraService.obtener(obraId);
        return presupuestoRepository.findByObraId(obraId)
                .orElseThrow(() -> new NoSuchElementException("La obra no tiene presupuesto: " + obraId));
    }

    /** Agrega (o suma cantidad a) un ítem tomando el precio vigente del catálogo. */
    public PresupuestoItem agregarItem(Long presupuestoId, Long materialId, double cantidad) {
        Presupuesto presupuesto = obtener(presupuestoId);
        exigirEditable(presupuesto);
        Material material = materialService.obtener(materialId);

        PresupuestoItem item = PresupuestoItem.builder()
                .presupuesto(presupuesto)
                .material(material)
                .cantidad(cantidad)
                .precioUnitario(material.getPrecioUnitario())
                .build();
        item.recalcularSubtotal();
        PresupuestoItem guardado = presupuestoItemRepository.save(item);
        recalcularTotal(presupuestoId);
        return guardado;
    }

    @Transactional(readOnly = true)
    public List<PresupuestoItem> listarItems(Long presupuestoId) {
        obtener(presupuestoId);
        return presupuestoItemRepository.findByPresupuestoId(presupuestoId);
    }

    public double recalcularTotal(Long presupuestoId) {
        Presupuesto presupuesto = obtener(presupuestoId);
        double total = presupuesto.calcularTotal(presupuestoItemRepository.findByPresupuestoId(presupuestoId));
        presupuestoRepository.save(presupuesto);
        return total;
    }

    /** BORRADOR -> APROBADO. */
    public Presupuesto aprobar(Long presupuestoId) {
        Presupuesto presupuesto = obtener(presupuestoId);
        if (presupuesto.getEstado() != EstadoPresupuesto.BORRADOR) {
            throw new IllegalStateException("Solo se aprueba un presupuesto en BORRADOR");
        }
        presupuesto.setEstado(EstadoPresupuesto.APROBADO);
        return presupuestoRepository.save(presupuesto);
    }

    /** Presupuesto.congelar() del diagrama, vía la propia entidad. */
    public Presupuesto congelar(Long presupuestoId) {
        Presupuesto presupuesto = obtener(presupuestoId);
        presupuesto.congelar();
        return presupuestoRepository.save(presupuesto);
    }

    private void exigirEditable(Presupuesto presupuesto) {
        if (presupuesto.getEstado() == EstadoPresupuesto.CONGELADO) {
            throw new IllegalStateException("El presupuesto está CONGELADO y ya no admite cambios");
        }
    }
}
