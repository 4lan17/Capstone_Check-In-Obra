package cl.duocuc.checkinobra.obra;

import java.security.SecureRandom;

/** Códigos válidos y distintos en cada corrida: la base de test no se vacía entre ejecuciones. */
final class CodigosDePrueba {

    private static final String ALFABETO = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private static final SecureRandom ALEATORIO = new SecureRandom();

    private CodigosDePrueba() {
    }

    static String unico() {
        StringBuilder codigo = new StringBuilder();
        for (int i = 0; i < 8; i++) {
            codigo.append(ALFABETO.charAt(ALEATORIO.nextInt(ALFABETO.length())));
        }
        return codigo.toString();
    }
}
