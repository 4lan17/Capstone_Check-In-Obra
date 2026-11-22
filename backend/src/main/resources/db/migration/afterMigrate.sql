-- Callback de Flyway: corre al terminar CADA migración, haya o no versiones pendientes.
--
-- Mejora #152 (origen: comentario del autor en #103, MT0): flyway_schema_history la crea Flyway, es
-- decir, después de que corre db/roles.sql, y el ALTER DEFAULT PRIVILEGES de ese archivo le daba
-- SELECT, INSERT, UPDATE y DELETE a checkinobra_app como a cualquier tabla. Una API comprometida
-- podía borrar o falsear el historial de migraciones. La tabla no es de datos: la API solo la lee.
--
-- Va como callback y no como migración versionada por tres razones:
--   * la tabla existe recién cuando Flyway termina de crearla, y esto es lo último que corre;
--   * corre en toda base que se migra, también en las dadas de alta después (MT7), sin un paso extra;
--   * corre aunque no haya migraciones pendientes, así que corrige las bases que ya existían.
--
-- Es idempotente, y no falla donde el rol de la API no existe (una base armada a mano, sin roles.sql).
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'checkinobra_app') THEN
        EXECUTE format(
            'REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON TABLE %I.flyway_schema_history FROM checkinobra_app',
            current_schema());
    END IF;
END
$$;
