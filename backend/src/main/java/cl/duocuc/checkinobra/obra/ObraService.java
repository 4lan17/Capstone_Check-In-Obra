package cl.duocuc.checkinobra.obra;

import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.EmpresaService;
import cl.duocuc.checkinobra.control.AlertaRepository;
import cl.duocuc.checkinobra.inventario.PrestamoHerramientaRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.NoSuchElementException;

@Service
@Transactional
public class ObraService {

    private final ObraRepository obraRepository;
    private final EmpresaService empresaService;
    private final PrestamoHerramientaRepository prestamoHerramientaRepository;
    private final AlertaRepository alertaRepository;

    public ObraService(
            ObraRepository obraRepository,
            EmpresaService empresaService,
            PrestamoHerramientaRepository prestamoHerramientaRepository,
            AlertaRepository alertaRepository) {
        this.obraRepository = obraRepository;
        this.empresaService = empresaService;
        this.prestamoHerramientaRepository = prestamoHerramientaRepository;
        this.alertaRepository = alertaRepository;
    }

    public Obra crear(Long empresaId, String nombre, String cliente, String ubicacion) {
        Empresa empresa = empresaService.obtener(empresaId);
        Obra obra = Obra.builder()
                .nombre(nombre)
                .cliente(cliente)
                .ubicacion(ubicacion)
                .estado(EstadoObra.ACTIVA)
                .empresa(empresa)
                .build();
        return obraRepository.save(obra);
    }

    @Transactional(readOnly = true)
    public List<Obra> listarPorEmpresa(Long empresaId) {
        return obraRepository.findByEmpresaId(empresaId);
    }

    @Transactional(readOnly = true)
    public Obra obtener(Long id) {
        return obraRepository.findById(id)
                .orElseThrow(() -> new NoSuchElementException("Obra no encontrada: " + id));
    }

    /**
     * Valida las precondiciones que el mockup ya anticipaba (sin
     * herramientas fuera, sin alertas sin resolver) y solo entonces
     * invoca Obra.cerrar().
     */
    public Obra cerrarObra(Long obraId) {
        Obra obra = obtener(obraId);

        long herramientasFuera = prestamoHerramientaRepository.findByObraIdAndFechaDevolRealIsNull(obraId).size();
        if (herramientasFuera > 0) {
            throw new IllegalStateException(
                    "No se puede cerrar la obra: quedan " + herramientasFuera + " herramientas sin devolver");
        }

        long alertasSinResolver = alertaRepository.findByObraIdAndResueltoFalse(obraId).size();
        if (alertasSinResolver > 0) {
            throw new IllegalStateException(
                    "No se puede cerrar la obra: quedan " + alertasSinResolver + " alertas sin resolver");
        }

        obra.cerrar();
        return obraRepository.save(obra);
    }
}
