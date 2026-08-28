package cl.duocuc.checkinobra.inventario;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface HerramientaRepository extends JpaRepository<Herramienta, Long> {
    List<Herramienta> findByEmpresaId(Long empresaId);
    Optional<Herramienta> findByCodigoQr(String codigoQr);
}
