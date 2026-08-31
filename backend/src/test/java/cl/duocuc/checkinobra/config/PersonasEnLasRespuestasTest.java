package cl.duocuc.checkinobra.config;

import cl.duocuc.checkinobra.inventario.KardexMovimiento;
import cl.duocuc.checkinobra.inventario.KardexMovimientoResponse;
import cl.duocuc.checkinobra.inventario.TipoMovimiento;
import cl.duocuc.checkinobra.obra.EstadoObra;
import cl.duocuc.checkinobra.obra.Obra;
import cl.duocuc.checkinobra.obra.ObraResponse;
import cl.duocuc.checkinobra.obra.Trabajador;
import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * El nombre y el RUT de una persona se muestran en tres lugares distintos —
 * quién dirige la obra, quién recibió un despacho, quién tiene una herramienta—
 * y en los tres puede no haber nadie todavía. Estas pruebas fijan que la
 * ausencia viaje como nulos limpios y no reviente el mapeo.
 */
class PersonasEnLasRespuestasTest {

    private Empresa empresa() {
        return Empresa.builder().id(1L).nombre("Constructora").rut("76.412.330-9").build();
    }

    private Usuario persona(String nombre, String rut, RolUsuario rol) {
        return Usuario.builder()
                .id(9L)
                .nombre(nombre)
                .rut(rut)
                .email("x@y.cl")
                .rol(rol)
                .empresa(empresa())
                .build();
    }

    private Obra obra(Usuario jefe) {
        return Obra.builder()
                .id(3L)
                .nombre("Los Almendros · Torre B")
                .cliente("Inmobiliaria Aconcagua")
                .ubicacion("Ñuñoa")
                .estado(EstadoObra.ACTIVA)
                .empresa(empresa())
                .jefeTerreno(jefe)
                .build();
    }

    @Test
    void la_obra_expone_al_jefe_con_nombre_y_rut() {
        var jefe = persona("Rodrigo Cárcamo", "14.109.556-2", RolUsuario.JEFE_TERRENO);

        ObraResponse r = ObraResponse.de(obra(jefe));

        assertThat(r.jefeTerrenoId()).isEqualTo(9L);
        assertThat(r.jefeTerrenoNombre()).isEqualTo("Rodrigo Cárcamo");
        assertThat(r.jefeTerrenoRut()).isEqualTo("14.109.556-2");
    }

    @Test
    void una_obra_sin_jefe_manda_los_tres_campos_en_nulo() {
        // No es lo mismo "todavía no le asignan jefe" que "no vino el dato".
        // Mandar los tres campos, nulos, deja al cliente distinguirlo.
        ObraResponse r = ObraResponse.de(obra(null));

        assertThat(r.jefeTerrenoId()).isNull();
        assertThat(r.jefeTerrenoNombre()).isNull();
        assertThat(r.jefeTerrenoRut()).isNull();
        assertThat(r.nombre()).isEqualTo("Los Almendros · Torre B");
    }

    @Test
    void un_despacho_distingue_a_quien_registra_de_quien_recibe() {
        var bodeguero = persona("Jorge Reyes", "15.220.884-7", RolUsuario.BODEGUERO);
        var receptor = Trabajador.builder()
                .id(4L)
                .usuario(persona("Marcelo Sepúlveda", "17.930.556-4", RolUsuario.TRABAJADOR))
                .build();

        var movimiento = KardexMovimiento.builder()
                .id(1L)
                .tipoMovimiento(TipoMovimiento.DESPACHO)
                .cantidad(36)
                .fecha(LocalDateTime.now())
                .obra(obra(null))
                .material(material())
                .usuario(bodeguero)
                .trabajador(receptor)
                .build();

        var r = KardexMovimientoResponse.de(movimiento);

        // Son dos personas distintas y la respuesta no puede confundirlas.
        assertThat(r.usuarioNombre()).isEqualTo("Jorge Reyes");
        assertThat(r.trabajadorNombre()).isEqualTo("Marcelo Sepúlveda");
        assertThat(r.trabajadorRut()).isEqualTo("17.930.556-4");
    }

    @Test
    void una_recepcion_no_tiene_receptor() {
        // El material entra desde un proveedor. El servicio además rechaza que
        // se mande un trabajador en una recepción.
        var movimiento = KardexMovimiento.builder()
                .id(1L)
                .tipoMovimiento(TipoMovimiento.RECEPCION)
                .cantidad(72)
                .fecha(LocalDateTime.now())
                .obra(obra(null))
                .material(material())
                .usuario(persona("Jorge Reyes", "15.220.884-7", RolUsuario.BODEGUERO))
                .build();

        var r = KardexMovimientoResponse.de(movimiento);

        assertThat(r.trabajadorId()).isNull();
        assertThat(r.trabajadorNombre()).isNull();
        assertThat(r.trabajadorRut()).isNull();
        assertThat(r.usuarioNombre()).isEqualTo("Jorge Reyes");
    }

    @Test
    void el_trabajador_toma_su_rut_del_usuario_y_no_lo_duplica() {
        var t = Trabajador.builder()
                .id(4L)
                .usuario(persona("Javier Ortiz", "19.775.310-4", RolUsuario.TRABAJADOR))
                .build();

        assertThat(t.rut()).isEqualTo("19.775.310-4");
        assertThat(t.nombre()).isEqualTo("Javier Ortiz");
    }

    private cl.duocuc.checkinobra.cubicacion.Material material() {
        return cl.duocuc.checkinobra.cubicacion.Material.builder()
                .id(2L)
                .sku("VOL-ST-10-120240")
                .nombre("Volcanita ST 10 mm")
                .categoria(cl.duocuc.checkinobra.cubicacion.CategoriaMaterial.VOLCANITA)
                .precioUnitario(5980)
                .stockMinimo(40)
                .empresa(empresa())
                .build();
    }
}
