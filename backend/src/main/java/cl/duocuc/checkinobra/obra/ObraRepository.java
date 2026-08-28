package cl.duocuc.checkinobra.obra;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface ObraRepository extends JpaRepository<Obra, Long> {
    List<Obra> findByEmpresaId(Long empresaId);
    List<Obra> findByEmpresaIdAndEstado(Long empresaId, EstadoObra estado);
}
