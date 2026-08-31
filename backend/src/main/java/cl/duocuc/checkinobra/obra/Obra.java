package cl.duocuc.checkinobra.obra;

import cl.duocuc.checkinobra.config.Usuario;
import cl.duocuc.checkinobra.config.PerteneceAEmpresa;
import cl.duocuc.checkinobra.config.Empresa;
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

@Entity
@Table(name = "obras")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Obra implements PerteneceAEmpresa {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String nombre;

    @Column(nullable = false)
    private String cliente;

    @Column(nullable = false)
    private String ubicacion;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private EstadoObra estado;

    /**
     * Quién dirige la obra. Nulo mientras no se le asigne: una obra puede
     * crearse antes de que se defina el jefe.
     */
    @ManyToOne(fetch = FetchType.EAGER)
    @JoinColumn(name = "jefe_terreno_id")
    private Usuario jefeTerreno;

    @ManyToOne(fetch = FetchType.EAGER, optional = false)
    @JoinColumn(name = "empresa_id", nullable = false)
    private Empresa empresa;

    /**
     * Obra.cerrar() del diagrama — transición pura de estado. Las
     * precondiciones (sin herramientas fuera, sin alertas sin resolver)
     * se validan en ObraService.cerrarObra(), que consulta otros
     * agregados antes de invocar este método.
     */
    public void cerrar() {
        if (this.estado == EstadoObra.CERRADA) {
            throw new IllegalStateException("La obra ya está cerrada");
        }
        this.estado = EstadoObra.CERRADA;
    }

    @Override
    public Long empresaId() {
        return empresa.getId();
    }
}
