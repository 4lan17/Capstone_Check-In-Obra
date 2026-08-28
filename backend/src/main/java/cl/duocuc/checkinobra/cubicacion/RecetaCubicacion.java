package cl.duocuc.checkinobra.cubicacion;

import java.util.List;

/**
 * Rendimientos por tipo de partida — el diagrama de clases NO modela una
 * tabla de recetas (Partida no se relaciona con Material salvo a través
 * de ItemCubicado, que ya es el resultado). Sin una regla así,
 * MotorCubicacion.calcular() no tiene qué calcular, así que esta clase
 * la agrega. Los coeficientes son valores de referencia orientativos —
 * hay que reemplazarlos por las tablas de rendimiento reales de la
 * constructora antes de usar el número en un presupuesto de verdad.
 */
final class RecetaCubicacion {

    record Coeficiente(CategoriaMaterial categoria, double cantidadPorM2, boolean porMontante) {
    }

    private RecetaCubicacion() {
    }

    static List<Coeficiente> para(TipoPartida tipo) {
        return switch (tipo) {
            case TABIQUE -> List.of(
                    // Volcanita a ambas caras del tabique.
                    new Coeficiente(CategoriaMaterial.VOLCANITA, 0.70, false),
                    // Montantes: no es por m², es por metro lineal de ancho / separación.
                    new Coeficiente(CategoriaMaterial.METALCOM, 0, true),
                    new Coeficiente(CategoriaMaterial.FIJACION, 0.05, false));
            case CIELO -> List.of(
                    new Coeficiente(CategoriaMaterial.VOLCANITA, 0.35, false),
                    new Coeficiente(CategoriaMaterial.METALCOM, 0.60, false),
                    new Coeficiente(CategoriaMaterial.FIJACION, 0.04, false));
            case REVESTIMIENTO -> List.of(
                    new Coeficiente(CategoriaMaterial.OSB, 0.35, false),
                    new Coeficiente(CategoriaMaterial.FIJACION, 0.03, false));
        };
    }
}
