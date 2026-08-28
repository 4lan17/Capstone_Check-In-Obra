package cl.duocuc.checkinobra.config;

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
public class Usuario {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String nombre;

    @Column(nullable = false, unique = true)
    private String email;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private RolUsuario rol;

    /** Hash BCrypt del PIN de 4 dígitos. Nulo para roles que solo entran por correo. */
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
}
