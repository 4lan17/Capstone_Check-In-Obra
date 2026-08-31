/// Refleja `UsuarioResponse` del backend.
class UsuarioEmpresa {
  const UsuarioEmpresa({
    required this.id,
    required this.nombre,
    required this.email,
    required this.rut,
    required this.rol,
  });

  final int id;
  final String nombre;
  final String email;

  /// Nulo solo para los usuarios anteriores a la migración V3; la API lo exige
  /// al crear uno nuevo.
  final String? rut;

  /// `RolUsuario`: ADMIN, JEFE_TERRENO, BODEGUERO o TRABAJADOR.
  final String rol;

  factory UsuarioEmpresa.desdeJson(Map<String, dynamic> j) => UsuarioEmpresa(
    id: j['id'] as int,
    nombre: j['nombre'] as String,
    email: j['email'] as String,
    rut: j['rut'] as String?,
    rol: j['rol'] as String,
  );
}

/// Refleja `EmpresaResponse`.
class Empresa {
  const Empresa({required this.id, required this.nombre, required this.rut});

  final int id;
  final String nombre;
  final String rut;

  factory Empresa.desdeJson(Map<String, dynamic> j) => Empresa(
    id: j['id'] as int,
    nombre: j['nombre'] as String,
    rut: j['rut'] as String,
  );
}
