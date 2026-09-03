package cl.duocuc.checkinobra.inventario;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

public interface HerramientaRepository extends JpaRepository<Herramienta, Long> {
    List<Herramienta> findByEmpresaId(Long empresaId);
    Optional<Herramienta> findByCodigoQr(String codigoQr);

    /**
     * Los códigos que ya existen de una tanda. Lo usa la importación masiva
     * para resolver en una consulta lo que si no serían cientos.
     */
    List<Herramienta> findByCodigoQrIn(Collection<String> codigos);
}
