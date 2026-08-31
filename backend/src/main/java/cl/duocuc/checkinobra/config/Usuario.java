package cl.duocuc.checkinobra.config;

import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.springframework.security.crypto.bcrypt.BCrypt;

/**
 * Usuario — una sola clase de autenticación para los 4 roles (RolUsuario).
 * El permiso efectivo depende de {@link #rol}, no de una subclase por rol.
 */
@Entity
@Table(name = "usuarios")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Usuario implements PerteneceAEmpresa {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String nombre;

    @Column(nullable = false, unique = true)
    private String email;

    /**
     * RUT de la persona. Vivía en {@code Trabajador}, y ahí no alcanzaba: un
     * jefe de terreno o un bodeguero no tienen registro de trabajador, así que
     * no había dónde guardar el suyo. Nulo solo para los usuarios anteriores a
     * la migración V3; la API lo exige al crear.
     */
    @Column(unique = true, length = 20)
    private String rut;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private RolUsuario rol;

    /**
     * Hash BCrypt del PIN de 4 dígitos. Nulo para roles que solo entran por correo.
     *
     * <p>{@code @JsonIgnore} es la red de seguridad, no la defensa principal: hoy
     * ningún controlador devuelve entidades, así que este campo no tiene por dónde
     * salir. La anotación cubre el día en que alguien agregue un endpoint que sí lo
     * haga —que es exactamente como se filtró antes— y cuesta una línea. Un hash
     * BCrypt de un PIN de 4 dígitos se rompe por fuerza bruta en el espacio de
     * 10 000 combinaciones, así que publicarlo equivale a publicar el PIN.
     */
    @JsonIgnore
    @Column(name = "pin_hash")
    private String pinHash;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "empresa_id", nullable = false)
    private Empresa empresa;

    /** Fija (o cambia) el PIN, guardando solo su hash — nunca el PIN en claro. */
    public void definirPin(String pinPlano) {
        if (pinPlano == null || !pinPlano.matches("\\d{4}")) {
            throw new IllegalArgumentException("El PIN debe tener 4 dígitos");
        }
        this.pinHash = BCrypt.hashpw(pinPlano, BCrypt.gensalt());
    }

    /** Usuario.autenticar(pin): boolean del diagrama. */
    public boolean autenticar(String pin) {
        if (pinHash == null || pin == null) {
            return false;
        }
        return BCrypt.checkpw(pin, pinHash);
    }

    /** Usuario.autenticarPorEmail(email): boolean del diagrama. */
    public boolean autenticarPorEmail(String email) {
        return email != null && email.equalsIgnoreCase(this.email);
    }

    @Override
    public Long empresaId() {
        return empresa.getId();
    }
}
