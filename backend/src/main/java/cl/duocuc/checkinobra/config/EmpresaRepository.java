package cl.duocuc.checkinobra.config;

import org.springframework.data.jpa.repository.JpaRepository;

public interface EmpresaRepository extends JpaRepository<Empresa, Long> {
    boolean existsByRut(String rut);
}
