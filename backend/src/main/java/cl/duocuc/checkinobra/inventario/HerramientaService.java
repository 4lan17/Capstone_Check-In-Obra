package cl.duocuc.checkinobra.inventario;

import cl.duocuc.checkinobra.config.AccesoEmpresa;
import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.EmpresaService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.NoSuchElementException;

@Service
@Transactional
public class HerramientaService {

    private final HerramientaRepository herramientaRepository;
    private final EmpresaService empresaService;

    public HerramientaService(HerramientaRepository herramientaRepository, EmpresaService empresaService) {
        this.herramientaRepository = herramientaRepository;
        this.empresaService = empresaService;
    }

    public Herramienta crear(
            Long empresaId, String codigoQr, String nombre, String categoria, double valorReposicion) {
        Empresa empresa = empresaService.obtener(empresaId);
        Herramienta herramienta = Herramienta.builder()
                .codigoQr(codigoQr)
                .nombre(nombre)
                .categoria(categoria)
                .valorReposicion(valorReposicion)
                .estado(EstadoHerramienta.DISPONIBLE)
                .empresa(empresa)
                .build();
        return herramientaRepository.save(herramienta);
    }

    @Transactional(readOnly = true)
    public List<Herramienta> listarPorEmpresa(Long empresaId) {
        AccesoEmpresa.exigirEmpresa(empresaId);
        return herramientaRepository.findByEmpresaId(empresaId);
    }

    @Transactional(readOnly = true)
    public Herramienta obtener(Long id) {
        return herramientaRepository.findById(id)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Herramienta no encontrada: " + id));
    }

    @Transactional(readOnly = true)
    public Herramienta buscarPorCodigoQr(String codigoQr) {
        return herramientaRepository.findByCodigoQr(codigoQr)
                .filter(AccesoEmpresa::esPropio)
                .orElseThrow(() -> new NoSuchElementException("Código no reconocido"));
    }
}
