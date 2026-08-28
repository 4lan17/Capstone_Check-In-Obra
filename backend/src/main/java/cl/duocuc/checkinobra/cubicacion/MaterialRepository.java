package cl.duocuc.checkinobra.cubicacion;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface MaterialRepository extends JpaRepository<Material, Long> {
    List<Material> findByEmpresaId(Long empresaId);
    List<Material> findByEmpresaIdAndCategoria(Long empresaId, CategoriaMaterial categoria);
    Optional<Material> findFirstByEmpresaIdAndCategoriaOrderByIdAsc(Long empresaId, CategoriaMaterial categoria);
    Optional<Material> findBySku(String sku);
}
