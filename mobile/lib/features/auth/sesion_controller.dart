import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/sesion_storage.dart';
import '../../data/api/auth_api.dart';

/// Estado de sesión de la app. `null` significa "nadie ha entrado".
///
/// Al arrancar lee el almacenamiento cifrado: si hay un token guardado, se
/// entra directo sin volver a pedir credenciales. En obra, tener que loguearse
/// cada vez que se abre la app es inaceptable.
class SesionController extends AsyncNotifier<SesionUsuario?> {
  SesionStorage get _storage => ref.read(sesionStorageProvider);
  AuthApi get _api => ref.read(authApiProvider);

  @override
  Future<SesionUsuario?> build() => _storage.leer();

  Future<void> entrarConCorreo({
    required String email,
    required String pin,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final sesion = await _api.login(email: email.trim(), pin: pin);
      await _storage.guardar(sesion);
      return sesion;
    });
  }

  Future<void> entrarConPin({
    required int usuarioId,
    required String pin,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final sesion = await _api.loginPorPin(usuarioId: usuarioId, pin: pin);
      await _storage.guardar(sesion);
      return sesion;
    });
  }

  /// Cierra la sesión pero recuerda al usuario, para que pueda volver a
  /// entrar solo con su PIN.
  Future<void> salir() async {
    await _storage.cerrarSesion();
    state = const AsyncValue.data(null);
  }

  /// Olvida también al usuario recordado — el "Cambiar" de la pantalla de PIN.
  Future<void> cambiarDeUsuario() async {
    await _storage.olvidarTodo();
    ref.invalidate(usuarioRecordadoProvider);
    state = const AsyncValue.data(null);
  }
}

final sesionProvider = AsyncNotifierProvider<SesionController, SesionUsuario?>(
  SesionController.new,
);

/// Último usuario que entró en este teléfono, si lo hay.
final usuarioRecordadoProvider = FutureProvider<UsuarioRecordado?>(
  (ref) => ref.watch(sesionStorageProvider).leerUsuarioRecordado(),
);

/// Nombre legible de cada valor del enum `RolUsuario` del backend.
String nombreDeRol(String rol) => switch (rol) {
  'ADMIN' => 'Administrador',
  'JEFE_TERRENO' => 'Jefe de terreno',
  'BODEGUERO' => 'Bodeguero',
  'TRABAJADOR' => 'Trabajador',
  _ => rol,
};
