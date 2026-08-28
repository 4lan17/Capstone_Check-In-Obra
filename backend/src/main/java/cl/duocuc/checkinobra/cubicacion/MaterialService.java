package cl.duocuc.checkinobra.cubicacion;

import cl.duocuc.checkinobra.config.Empresa;
import cl.duocuc.checkinobra.config.EmpresaService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.NoSuchElementException;

@Service
@Transactional
public class MaterialService {

    private final MaterialRepository materialRepository;
    private final EmpresaService empresaService;

    public MaterialService(MaterialRepository materialRepository, EmpresaService empresaService) {
        this.materialRepository = materialRepository;
        this.empresaService = empresaService;
    }

    public Material crear(
            Long empresaId, String sku, String nombre, CategoriaMaterial categoria,
            double precioUnitario, double stockMinimo) {
        if (materialRepository.findBySku(sku).isPresent()) {
            throw new IllegalStateException("Ya existe un material con ese SKU");
        }
        Empresa empresa = empresaService.obtener(empresaId);
        Material material = Material.builder()
                .sku(sku)
                .nombre(nombre)
                .categoria(categoria)
                .precioUnitario(precioUnitario)
                .stockMinimo(stockMinimo)
                .empresa(empresa)
                .build();
        return materialRepository.save(material);
    }

    @Transactional(readOnly = true)
    public List<Material> listarPorEmpresa(Long empresaId) {
        return materialRepository.findByEmpresaId(empresaId);
    }

    @Transactional(readOnly = true)
    public List<Material> listarPorEmpresaYCategoria(Long empresaId, CategoriaMaterial categoria) {
        return materialRepository.findByEmpresaIdAndCategoria(empresaId, categoria);
    }

    @Transactional(readOnly = true)
    public Material obtener(Long id) {
        return materialRepository.findById(id)
                .orElseThrow(() -> new NoSuchElementException("Material no encontrado: " + id));
    }

    public Material actualizarPrecio(Long materialId, double nuevoPrecio) {
        Material material = obtener(materialId);
        material.setPrecioUnitario(nuevoPrecio);
        return materialRepository.save(material);
    }
}
