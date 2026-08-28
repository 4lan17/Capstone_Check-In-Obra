package cl.duocuc.checkinobra.obra;

import cl.duocuc.checkinobra.config.Usuario;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToOne;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * Trabajador — la "extensión" de Usuario cuando rol = TRABAJADOR
 * (Usuario "1" -- "0..1" Trabajador : extiende). Un mismo mecanismo de
 * autenticación (Usuario) para los 4 roles; este registro agrega solo
 * los datos propios de terreno.
 */
@Entity
@Table(name = "trabajadores")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Trabajador {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private String rut;

    /** Payload del QR de la credencial que escanea el bodeguero. */
    @Column(name = "credencial_qr", unique = true)
    private String credencialQr;

    @OneToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "usuario_id", nullable = false, unique = true)
    private Usuario usuario;

    @ManyToOne(fetch = FetchType.EAGER)
    @JoinColumn(name = "cuadrilla_id")
    private Cuadrilla cuadrilla;
}
