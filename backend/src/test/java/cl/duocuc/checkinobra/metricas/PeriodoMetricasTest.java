package cl.duocuc.checkinobra.metricas;

import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/** El periodo de las métricas (#203): 7d, 30d u obra; semanas ISO, S1..Sn, y la granularidad. */
class PeriodoMetricasTest {

    // Miércoles 2026-11-25.
    private static final LocalDate HOY = LocalDate.of(2026, 11, 25);

    @Test
    void sinParametroEsDe30Dias() {
        PeriodoMetricas p = PeriodoMetricas.resolver(null, HOY, null);

        assertThat(p.codigo()).isEqualTo("30d");
        assertThat(p.desde()).isEqualTo(HOY.minusDays(29));
        assertThat(p.hasta()).isEqualTo(HOY);
        assertThat(p.dias()).isEqualTo(30);
    }

    @Test
    void sieteDiasIncluyeHoy() {
        PeriodoMetricas p = PeriodoMetricas.resolver("7d", HOY, null);

        assertThat(p.desde()).isEqualTo(HOY.minusDays(6));
        assertThat(p.dias()).isEqualTo(7);
    }

    @Test
    void obraEmpiezaEnElInicioDado_OEnHoySiNoHay() {
        assertThat(PeriodoMetricas.resolver("obra", HOY, LocalDate.of(2026, 9, 1)).desde()).isEqualTo(LocalDate.of(2026, 9, 1));
        assertThat(PeriodoMetricas.resolver("obra", HOY, null).desde()).isEqualTo(HOY);
        assertThat(PeriodoMetricas.resolver("obra", HOY, null).dias()).isEqualTo(1);
    }

    @Test
    void unInicioFuturoSeAcotaAHoy() {
        assertThat(PeriodoMetricas.resolver("obra", HOY, HOY.plusDays(3)).desde()).isEqualTo(HOY);
    }

    @Test
    void ignoraMayusculasYEspacios() {
        assertThat(PeriodoMetricas.resolver(" 7D ", HOY, null).codigo()).isEqualTo("7d");
        assertThat(PeriodoMetricas.resolver("OBRA", HOY, null).codigo()).isEqualTo("obra");
    }

    @Test
    void cualquierOtraCosaEsInvalida() {
        for (String malo : new String[] {"90d", "1y", "", "semana", "7"}) {
            assertThatThrownBy(() -> PeriodoMetricas.resolver(malo, HOY, null))
                    .as("«%s»", malo).isInstanceOf(IllegalArgumentException.class)
                    .hasMessageContaining("7d").hasMessageContaining("30d").hasMessageContaining("obra");
        }
    }

    @Test
    void granularidadPorDiaHastaLos31DiasYPorSemanaDespues() {
        assertThat(PeriodoMetricas.resolver("obra", HOY, HOY.minusDays(30)).dias()).isEqualTo(31);
        assertThat(PeriodoMetricas.resolver("obra", HOY, HOY.minusDays(30)).porSemana()).isFalse();
        assertThat(PeriodoMetricas.resolver("obra", HOY, HOY.minusDays(31)).dias()).isEqualTo(32);
        assertThat(PeriodoMetricas.resolver("obra", HOY, HOY.minusDays(31)).porSemana()).isTrue();
        assertThat(PeriodoMetricas.resolver("30d", HOY, null).porSemana()).isFalse();
    }

    @Test
    void lasSemanasSonIsoDesdeElLunesDeLaPrimeraYEtiquetadasDesdeS1() {
        // 30d desde el 2026-10-27 (martes) hasta el miércoles 2026-11-25.
        List<PeriodoMetricas.Semana> semanas = PeriodoMetricas.resolver("30d", HOY, null).semanas();

        assertThat(semanas).hasSize(5);
        assertThat(semanas.get(0).etiqueta()).isEqualTo("S1");
        assertThat(semanas.get(0).desde()).isEqualTo(LocalDate.of(2026, 10, 26)); // lunes
        assertThat(semanas.get(4).etiqueta()).isEqualTo("S5");
        assertThat(semanas.get(4).desde()).isEqualTo(LocalDate.of(2026, 11, 23));
    }

    @Test
    void unPeriodoDeUnDiaTieneUnaSemana() {
        assertThat(PeriodoMetricas.resolver("obra", HOY, null).semanas()).hasSize(1);
    }
}
