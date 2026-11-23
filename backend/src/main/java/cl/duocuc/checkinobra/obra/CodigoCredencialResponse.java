package cl.duocuc.checkinobra.obra;

import java.time.Instant;

/**
 * Lo que recibe el teléfono del trabajador al pedir un código: el código, cuándo vence y cuánto dura.
 * La app lo muestra como {@code K7M2-9QXP} y lo renueva antes de que venza.
 */
public record CodigoCredencialResponse(String codigo, Instant expiraEn, int vigenciaSegundos) {
}
