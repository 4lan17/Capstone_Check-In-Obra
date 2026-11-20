-- Roles de base de datos de Check-In-Obra (SEG6 #94 y MT0 #103).
--
--   checkinobra_migrador  DUEÑO del esquema: crea y altera tablas. Solo lo usa Flyway.
--   checkinobra_app       SOLO DML (SELECT, INSERT, UPDATE, DELETE). Es el usuario de la API.
--
-- Ninguno es superusuario. Si la API se compromete, quien la controla puede leer
-- y escribir datos pero no borrar tablas, cambiar el esquema ni tocar otras bases.
--
-- Es IDEMPOTENTE: sirve en una base nueva (la corre el entrypoint de Postgres) y
-- en una que ya existía con las tablas a nombre del superusuario (le pasa la
-- propiedad al migrador). También sincroniza las contraseñas con las del .env.
--
-- Variables de psql (-v): app_password, migrador_password.
-- Uso: psql -v ON_ERROR_STOP=1 -v app_password=... -v migrador_password=... -f roles.sql
\set ON_ERROR_STOP on

-- Roles ---------------------------------------------------------------------
SELECT 'CREATE ROLE checkinobra_app LOGIN'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'checkinobra_app') \gexec
SELECT 'CREATE ROLE checkinobra_migrador LOGIN'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'checkinobra_migrador') \gexec

ALTER ROLE checkinobra_app NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS LOGIN;
ALTER ROLE checkinobra_migrador NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS LOGIN;
SELECT format('ALTER ROLE checkinobra_app PASSWORD %L', :'app_password') \gexec
SELECT format('ALTER ROLE checkinobra_migrador PASSWORD %L', :'migrador_password') \gexec

-- Conexión y esquema --------------------------------------------------------
SELECT format('GRANT CONNECT ON DATABASE %I TO checkinobra_app, checkinobra_migrador', current_database()) \gexec
ALTER SCHEMA public OWNER TO checkinobra_migrador;
GRANT USAGE ON SCHEMA public TO checkinobra_app;

-- Objetos que ya existían a nombre de otro rol (una base creada antes de esto):
-- pasan al migrador, que es quien debe poder alterarlos en las próximas
-- migraciones. Las secuencias ligadas a una columna siguen a su tabla.
DO $$
DECLARE
    objeto record;
BEGIN
    FOR objeto IN
        SELECT c.relkind, n.nspname, c.relname
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        JOIN pg_roles dueno ON dueno.oid = c.relowner
        WHERE n.nspname = 'public'
          AND c.relkind IN ('r', 'p', 'v', 'm', 'S')
          AND dueno.rolname <> 'checkinobra_migrador'
          AND NOT (c.relkind = 'S' AND EXISTS (
                SELECT 1 FROM pg_depend d WHERE d.objid = c.oid AND d.deptype IN ('a', 'i')))
        ORDER BY CASE c.relkind WHEN 'S' THEN 2 ELSE 1 END
    LOOP
        EXECUTE format('ALTER %s %I.%I OWNER TO checkinobra_migrador',
                CASE objeto.relkind WHEN 'S' THEN 'SEQUENCE' WHEN 'v' THEN 'VIEW'
                     WHEN 'm' THEN 'MATERIALIZED VIEW' ELSE 'TABLE' END,
                objeto.nspname, objeto.relname);
    END LOOP;
END
$$;

-- Permisos de la API: solo datos ---------------------------------------------
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO checkinobra_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO checkinobra_app;

-- Lo que el migrador cree de aquí en adelante queda accesible para la API sin
-- tener que acordarse de un GRANT en cada migración.
ALTER DEFAULT PRIVILEGES FOR ROLE checkinobra_migrador IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO checkinobra_app;
ALTER DEFAULT PRIVILEGES FOR ROLE checkinobra_migrador IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO checkinobra_app;
