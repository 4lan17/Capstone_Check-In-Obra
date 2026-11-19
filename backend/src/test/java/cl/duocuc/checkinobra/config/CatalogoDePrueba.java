package cl.duocuc.checkinobra.config;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

/**
 * Registra en el catálogo a las empresas y usuarios que una prueba crea directo en la
 * base, para que el login por correo los encuentre en el índice.
 *
 * <p>Las empresas de prueba comparten una sola base, así que se registran con un nombre
 * de base ficticio y distinto cada una (el catálogo exige uno único por empresa); el
 * resolutor de pruebas no lo usa.
 */
@Component
@ConditionalOnProperty(name = "checkinobra.pruebas.conexion-compartida", havingValue = "true")
class CatalogoDePrueba {

    private final CatalogoDeEmpresas catalogo;

    CatalogoDePrueba(CatalogoDeEmpresas catalogo) {
        this.catalogo = catalogo;
    }

    /** La empresa queda en el catálogo; hace falta antes de indexar sus correos. */
    void registrar(Empresa empresa) {
        catalogo.registrar(empresa.getId(), empresa.getRut(), empresa.getNombre(),
                "prueba_" + empresa.getId() + "_" + System.nanoTime(), "usuario_de_prueba", "env:NO_SE_USA");
    }

    /** El correo del usuario queda en el índice de login. */
    void indexar(Usuario usuario) {
        catalogo.reservarCorreo(usuario.getEmail(), usuario.getEmpresa().getId());
    }
}
