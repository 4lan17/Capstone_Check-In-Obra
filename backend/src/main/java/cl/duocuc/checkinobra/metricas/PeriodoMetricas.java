package cl.duocuc.checkinobra.metricas;

import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.time.temporal.TemporalAdjusters;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * El periodo que mira una métrica: {@code 7d} y {@code 30d} son los últimos 7 o 30 días contando hoy;
 * {@code obra} es desde que la obra empezó a moverse. Siempre termina hoy, en America/Santiago.
 *
 * <p>Las semanas son ISO (de lunes a domingo) y se etiquetan {@code S1..Sn} contando desde la primera
 * semana del periodo, aunque esa semana haya empezado antes que el periodo.
 */
record PeriodoMetricas(String codigo, LocalDate desde, LocalDate hasta) {

    static final String POR_DEFECTO = "30d";
    /** Hasta este largo (en días) se grafica por día; más allá, por semana. */
    static final int MAXIMO_DE_DIAS_POR_DIA = 31;

    record Semana(String etiqueta, LocalDate desde) {
    }

    /**
     * @param parametro lo que vino en {@code ?periodo=}; nulo es el valor por defecto
     * @param inicio    desde cuándo cuenta {@code obra} (nulo: no hay historial, es solo hoy)
     * @throws IllegalArgumentException si no es {@code 7d}, {@code 30d} ni {@code obra}
     */
    static PeriodoMetricas resolver(String parametro, LocalDate hoy, LocalDate inicio) {
        String codigo = parametro == null ? POR_DEFECTO : parametro.trim().toLowerCase(Locale.ROOT);
        return switch (codigo) {
            case "7d" -> new PeriodoMetricas(codigo, hoy.minusDays(6), hoy);
            case "30d" -> new PeriodoMetricas(codigo, hoy.minusDays(29), hoy);
            case "obra" -> new PeriodoMetricas(codigo, inicio == null || inicio.isAfter(hoy) ? hoy : inicio, hoy);
            default -> throw new IllegalArgumentException("El periodo debe ser 7d, 30d u obra");
        };
    }

    /** Días que abarca, contando el primero y el último. */
    int dias() {
        return (int) ChronoUnit.DAYS.between(desde, hasta) + 1;
    }

    boolean porSemana() {
        return dias() > MAXIMO_DE_DIAS_POR_DIA;
    }

    static LocalDate lunesDe(LocalDate dia) {
        return dia.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY));
    }

    List<Semana> semanas() {
        List<Semana> semanas = new ArrayList<>();
        LocalDate ultima = lunesDe(hasta);
        int numero = 1;
        for (LocalDate lunes = lunesDe(desde); !lunes.isAfter(ultima); lunes = lunes.plusWeeks(1)) {
            semanas.add(new Semana("S" + numero++, lunes));
        }
        return semanas;
    }
}
