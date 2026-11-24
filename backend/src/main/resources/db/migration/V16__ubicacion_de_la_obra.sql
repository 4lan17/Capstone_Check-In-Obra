-- #204: la obra tiene una ubicación en el mapa, además del texto de `ubicacion` (que no cambia).
--
-- NUMERIC(9,6): seis decimales son ~11 cm, de sobra para un punto de obra, y caben los ±180 de la
-- longitud. Son opcionales (una obra puede crearse sin ubicar) pero siempre van juntas: una latitud
-- sin longitud no ubica nada. Los rangos son los de la Tierra. Se hace cumplir acá y no solo en la API,
-- para que una escritura que se salte el servicio no deje coordenadas imposibles.
--
-- Flyway corre esta migración por cada base de empresa.
ALTER TABLE obras
    ADD COLUMN latitud  NUMERIC(9, 6),
    ADD COLUMN longitud NUMERIC(9, 6),
    ADD CONSTRAINT ck_obras_ubicacion CHECK (
        (latitud IS NULL AND longitud IS NULL)
        OR (latitud IS NOT NULL AND longitud IS NOT NULL
            AND latitud BETWEEN -90 AND 90
            AND longitud BETWEEN -180 AND 180));
