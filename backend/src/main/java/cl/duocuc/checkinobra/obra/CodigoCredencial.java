package cl.duocuc.checkinobra.obra;

import cl.duocuc.checkinobra.config.PerteneceAEmpresa;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
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

import java.time.Instant;

/**
 * Un código de credencial de vida corta (SEG13, S-27): lo que el teléfono del trabajador muestra y el
 * bodeguero escanea. Vive en el servidor con su expiración; no es un token firmado, así que se puede
 * revocar. {@link #getCodigo()} va normalizado: mayúsculas, sin guiones ni espacios.
 */
@Entity
@Table(name = "codigos_credencial")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class CodigoCredencial implements PerteneceAEmpresa {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, length = 8, unique = true)
    private String codigo;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "trabajador_id", nullable = false)
    private Trabajador trabajador;

    @Column(name = "creado_en", nullable = false)
    private Instant creadoEn;

    @Column(name = "expira_en", nullable = false)
    private Instant expiraEn;

    public boolean vencidoEn(Instant instante) {
        return !expiraEn.isAfter(instante);
    }

    @Override
    public Long empresaId() {
        return trabajador.empresaId();
    }
}
