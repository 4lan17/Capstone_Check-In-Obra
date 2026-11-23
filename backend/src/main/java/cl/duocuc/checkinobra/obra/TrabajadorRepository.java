package cl.duocuc.checkinobra.obra;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface TrabajadorRepository extends JpaRepository<Trabajador, Long> {
    Optional<Trabajador> findByUsuarioId(Long usuarioId);
    /** El RUT vive en Usuario desde V3, así que la búsqueda cruza la relación. */
    Optional<Trabajador> findByUsuarioRut(String rut);
    List<Trabajador> findByCuadrillaId(Long cuadrillaId);
    List<Trabajador> findByCuadrilla_ObraId(Long obraId);
}
