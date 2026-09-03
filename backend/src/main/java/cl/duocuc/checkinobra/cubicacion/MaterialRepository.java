package cl.duocuc.checkinobra.cubicacion;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

public interface MaterialRepository extends JpaRepository<Material, Long> {
    List<Material> findByEmpresaId(Long empresaId);
    List<Material> findByEmpresaIdAndCategoria(Long empresaId, CategoriaMaterial categoria);
    Optional<Material> findFirstByEmpresaIdAndCategoriaOrderByIdAsc(Long empresaId, CategoriaMaterial categoria);
    Optional<Material> findBySku(String sku);

    /**
     * Las dos búsquedas del escáner. Van por empresa y no por el código suelto
     * a propósito: un SKU es único en toda la base, así que buscarlo sin filtrar
     * dejaría a un bodeguero resolviendo códigos de otra constructora con solo
     * apuntar la cámara.
     */
    Optional<Material> findByEmpresaIdAndSku(Long empresaId, String sku);

    Optional<Material> findByEmpresaIdAndCodigoBarra(Long empresaId, String codigoBarra);

    Optional<Material> findBySkuIgnoreCase(String sku);

    /**
     * Los que ya existen de una tanda de códigos. Es lo que usa la importación
     * masiva para no preguntar fila por fila: con el tope de 2.000 filas, una
     * consulta por fila son miles de idas a la base para responder algo que
     * cabe en una.
     */
    List<Material> findBySkuIn(Collection<String> skus);

    List<Material> findByEmpresaIdAndCodigoBarraIn(Long empresaId, Collection<String> codigosBarra);
}
