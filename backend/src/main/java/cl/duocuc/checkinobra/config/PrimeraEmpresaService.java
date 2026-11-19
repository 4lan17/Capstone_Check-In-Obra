package cl.duocuc.checkinobra.config;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Locale;

/**
 * Crea la primera empresa y su administrador en una base vacía (MT1, #104).
 *
 * <p>La migración V2 sembraba una empresa y un ADMIN en cada base nueva. Eso sale
 * de {@code db/migration}: el ADMIN se crea al dar de alta la empresa, no en cada
 * base. Mientras no exista el módulo de plataforma que da de alta empresas, la
 * primera nace al arrancar, con la clave de {@code PRIMER_ADMIN_CLAVE}, y su
 * administrador queda obligado a cambiarla en su primer ingreso (SEG3).
 */
@Service
@Transactional
public class PrimeraEmpresaService {

    static final String NOMBRE_DEL_ADMIN = "Administrador Check-In-Obra";

    private final EmpresaRepository empresaRepository;
    private final UsuarioRepository usuarioRepository;

    public PrimeraEmpresaService(EmpresaRepository empresaRepository, UsuarioRepository usuarioRepository) {
        this.empresaRepository = empresaRepository;
        this.usuarioRepository = usuarioRepository;
    }

    /**
     * Crea la empresa y su ADMIN si la base no tiene ninguna empresa todavía.
     *
     * @return {@code true} si las creó; {@code false} si no hizo nada (sin clave, o ya hay empresas)
     * @throws IllegalStateException si la clave es un valor de ejemplo
     * @throws IllegalArgumentException si la clave no cumple la política de claves
     */
    public boolean crearSiNoHay(String rut, String nombre, String adminEmail, String clave) {
        if (clave == null || clave.isBlank()) {
            return false;
        }
        if (clave.trim().toLowerCase(Locale.ROOT).startsWith("cambiar")) {
            throw new IllegalStateException(
                    "PRIMER_ADMIN_CLAVE es un valor de ejemplo. Define una clave propia de 8 o más caracteres.");
        }
        if (empresaRepository.count() > 0) {
            return false;
        }
        // La clave se valida antes de guardar nada: una clave débil no debe dejar
        // una empresa sin administrador.
        Usuario admin = Usuario.builder()
                .nombre(NOMBRE_DEL_ADMIN)
                .email(adminEmail.trim())
                .rol(RolUsuario.ADMIN)
                .build();
        admin.definirPin(clave);
        admin.setDebeCambiarPin(true);

        Empresa empresa = empresaRepository.save(Empresa.builder().nombre(nombre).rut(rut).build());
        admin.setEmpresa(empresa);
        usuarioRepository.save(admin);
        return true;
    }
}
