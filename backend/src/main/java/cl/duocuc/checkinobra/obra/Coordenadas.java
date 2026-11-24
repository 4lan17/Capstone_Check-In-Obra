package cl.duocuc.checkinobra.obra;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * Un punto en el mapa, ya validado: latitud entre -90 y 90, longitud entre -180 y 180, con seis
 * decimales (lo que guarda {@code obras}, V16). Son siempre un par.
 */
record Coordenadas(BigDecimal latitud, BigDecimal longitud) {

    private static final int DECIMALES = 6;
    private static final double LATITUD_MAXIMA = 90;
    private static final double LONGITUD_MAXIMA = 180;

    /**
     * Las dos coordenadas opcionales de un alta: ambas o ninguna.
     *
     * @return el punto, o {@code null} si no vino ninguna
     * @throws IllegalArgumentException si vino una sola o alguna está fuera de rango
     */
    static Coordenadas opcionales(Double latitud, Double longitud) {
        if (latitud == null && longitud == null) {
            return null;
        }
        if (latitud == null || longitud == null) {
            throw new IllegalArgumentException(
                    "La ubicación en el mapa necesita latitud y longitud, o ninguna de las dos");
        }
        return validar(latitud, longitud);
    }

    /** Las dos coordenadas de un cambio de ubicación: se piden las dos. */
    static Coordenadas obligatorias(Double latitud, Double longitud) {
        if (latitud == null || longitud == null) {
            throw new IllegalArgumentException("Falta la ubicación: indica la latitud y la longitud");
        }
        return validar(latitud, longitud);
    }

    private static Coordenadas validar(double latitud, double longitud) {
        if (!Double.isFinite(latitud) || Math.abs(latitud) > LATITUD_MAXIMA) {
            throw new IllegalArgumentException("La latitud debe estar entre -90 y 90");
        }
        if (!Double.isFinite(longitud) || Math.abs(longitud) > LONGITUD_MAXIMA) {
            throw new IllegalArgumentException("La longitud debe estar entre -180 y 180");
        }
        return new Coordenadas(redondear(latitud), redondear(longitud));
    }

    private static BigDecimal redondear(double valor) {
        return BigDecimal.valueOf(valor).setScale(DECIMALES, RoundingMode.HALF_UP);
    }
}
