import '../../core/network/api_client.dart';

/// Respuesta de `POST /api/auth/login` — refleja
/// `AuthController.LoginResponse` del backend.
class SesionUsuario {
  const SesionUsuario({
    required this.token,
    required this.usuarioId,
    required this.nombre,
    required this.rol,
    required this.empresaId,
  });

  final String token;
  final int usuarioId;
  final String nombre;

  /// Valor del enum `RolUsuario`: ADMIN, JEFE_TERRENO, BODEGUERO, TRABAJADOR.
  final String rol;
  final int empresaId;

  factory SesionUsuario.desdeJson(Map<String, dynamic> json) => SesionUsuario(
    token: json['token'] as String,
    usuarioId: json['usuarioId'] as int,
    nombre: json['nombre'] as String,
    rol: json['rol'] as String,
    empresaId: json['empresaId'] as int,
  );

  Map<String, dynamic> aJson() => {
    'token': token,
    'usuarioId': usuarioId,
    'nombre': nombre,
    'rol': rol,
    'empresaId': empresaId,
  };
}

/// Se lanza cuando el servidor respondió pero rechazó la petición
/// (por ejemplo, credenciales incorrectas).
class ApiException implements Exception {
  const ApiException(this.statusCode, this.mensaje);

  final int statusCode;
  final String mensaje;

  @override
  String toString() => 'ApiException($statusCode): $mensaje';
}

class AuthApi {
  AuthApi(this._client);

  final ApiClient _client;

  /// Login por correo + PIN. En el backend, el correo ubica al usuario
  /// (`Usuario.autenticarPorEmail`) y el PIN lo autentica (`Usuario.autenticar`).
  Future<SesionUsuario> login({required String email, required String pin}) =>
      _postLogin('/api/auth/login', {'email': email, 'pin': pin});

  /// Login solo con PIN, para el usuario que el teléfono ya recuerda.
  /// Es la vía del rol TRABAJADOR: nadie escribe un correo con guantes puestos.
  Future<SesionUsuario> loginPorPin({
    required int usuarioId,
    required String pin,
  }) => _postLogin('/api/auth/login-pin', {'usuarioId': usuarioId, 'pin': pin});

  Future<SesionUsuario> _postLogin(
    String ruta,
    Map<String, dynamic> cuerpo,
  ) async {
    final respuesta = await _client.dio.post<Map<String, dynamic>>(
      ruta,
      data: cuerpo,
    );

    final codigo = respuesta.statusCode ?? 0;
    if (codigo == 200 && respuesta.data != null) {
      return SesionUsuario.desdeJson(respuesta.data!);
    }
    throw ApiException(codigo, _mensajeDeError(respuesta.data, codigo));
  }

  /// El backend responde errores con el formato de `ApiExceptionHandler`:
  /// `{instante, status, mensaje}`.
  String _mensajeDeError(Map<String, dynamic>? cuerpo, int codigo) {
    final mensaje = cuerpo?['mensaje'];
    if (mensaje is String && mensaje.isNotEmpty) return mensaje;
    return switch (codigo) {
      400 => 'Correo o PIN incorrectos',
      403 => 'Sin autorización para esta acción',
      404 => 'Ruta no encontrada — ¿es la URL correcta del backend?',
      _ => 'El servidor respondió con código $codigo',
    };
  }
}
