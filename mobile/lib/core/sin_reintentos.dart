/// Riverpod 3 reintenta solo los providers que fallan. La app no lo quiere:
/// un error de red debe llegar a la pantalla, que ofrece «Reintentar», en vez
/// de dejarla cargando mientras se repite la llamada en silencio.
Duration? sinReintentos(int cuenta, Object error) => null;
