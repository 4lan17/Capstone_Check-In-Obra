package cl.duocuc.checkinobra.importacion;

/** Lee números escritos como los escribe la gente en una planilla. */
public final class Numeros {

    private Numeros() {
    }

    /**
     * Convierte el texto de una celda a número.
     *
     * <p>El caso difícil es el punto: en Chile "5.980" son cinco mil novecientos
     * ochenta, y en el formato de Estados Unidos son cinco coma noventa y ocho.
     * La regla que se aplica es la que resuelve bien lo que de verdad llega a
     * un catálogo de materiales:
     *
     * <ul>
     *   <li>con coma y punto ("12.500,75"), el punto separa miles y la coma decimales;</li>
     *   <li>con coma sola ("12,5"), la coma es el decimal;</li>
     *   <li>con punto solo, es separador de miles <b>si</b> deja exactamente tres
     *       dígitos detrás ("5.980" → 5980) y decimal en cualquier otro caso
     *       ("12.5" → 12,5).</li>
     * </ul>
     *
     * <p>Queda un caso que se lee mal: "2.500" escrito con intención de dos coma
     * cinco. Es la ambigüedad del formato, no del lector, y se resuelve del lado
     * de es-CL porque esta es la planilla de una constructora chilena.
     */
    public static double decimal(String texto, String campo) {
        String limpio = texto.replace("$", "").replace(" ", "").replace(" ", "").trim();
        if (limpio.isEmpty()) {
            throw new IllegalArgumentException(campo + " está vacío");
        }

        if (limpio.contains(",")) {
            limpio = limpio.replace(".", "").replace(",", ".");
        } else {
            int ultimoPunto = limpio.lastIndexOf('.');
            boolean separadorDeMiles = ultimoPunto > 0 && limpio.length() - ultimoPunto - 1 == 3;
            if (separadorDeMiles) {
                limpio = limpio.replace(".", "");
            }
        }

        try {
            double valor = Double.parseDouble(limpio);
            if (Double.isNaN(valor) || Double.isInfinite(valor)) {
                throw new NumberFormatException(limpio);
            }
            return valor;
        } catch (NumberFormatException e) {
            throw new IllegalArgumentException(campo + " no es un número válido: '" + texto + "'");
        }
    }

    /** Igual que {@link #decimal}, pero rechaza los negativos. */
    public static double noNegativo(String texto, String campo) {
        double valor = decimal(texto, campo);
        if (valor < 0) {
            throw new IllegalArgumentException(campo + " no puede ser negativo");
        }
        return valor;
    }

    /** Texto obligatorio, recortado y con el largo que aguanta la columna. */
    public static String obligatorio(String texto, String campo, int largoMaximo) {
        String limpio = texto.trim();
        if (limpio.isEmpty()) {
            throw new IllegalArgumentException(campo + " es obligatorio");
        }
        if (limpio.length() > largoMaximo) {
            throw new IllegalArgumentException(campo + " supera los " + largoMaximo + " caracteres");
        }
        return limpio;
    }

    /** Texto opcional: devuelve {@code null} si la celda viene en blanco. */
    public static String opcional(String texto, String campo, int largoMaximo) {
        String limpio = texto.trim();
        if (limpio.isEmpty()) {
            return null;
        }
        if (limpio.length() > largoMaximo) {
            throw new IllegalArgumentException(campo + " supera los " + largoMaximo + " caracteres");
        }
        return limpio;
    }
}
