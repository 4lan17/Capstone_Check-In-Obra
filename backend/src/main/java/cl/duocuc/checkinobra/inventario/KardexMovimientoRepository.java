package cl.duocuc.checkinobra.inventario;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface KardexMovimientoRepository extends JpaRepository<KardexMovimiento, Long> {
    List<KardexMovimiento> findByObraId(Long obraId);
    List<KardexMovimiento> findByObraIdAndMaterialId(Long obraId, Long materialId);
    List<KardexMovimiento> findByMaterialId(Long materialId);
}
