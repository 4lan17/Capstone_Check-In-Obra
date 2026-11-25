package cl.duocuc.checkinobra.obra;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface ObraRepository extends JpaRepository<Obra, Long> {
    /**
     * Por nombre y, si dos se llaman igual, por id. Sin ORDER BY Postgres devuelve las filas en el orden
     * en que están en disco, y un UPDATE deja la versión nueva al final: una obra pasaba al último lugar
     * de la lista cada vez que se la modificaba.
     */
    List<Obra> findByEmpresaIdOrderByNombreAscIdAsc(Long empresaId);
    List<Obra> findByEmpresaIdAndEstado(Long empresaId, EstadoObra estado);
}
