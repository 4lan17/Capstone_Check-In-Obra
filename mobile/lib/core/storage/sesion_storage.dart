import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/api/auth_api.dart';
import '../../data/modelos/perfil_trabajador.dart';

/// Guarda la sesión en el almacenamiento cifrado del dispositivo
/// (Keystore en Android). Nunca en SharedPreferences: ahí el JWT quedaría
/// legible para cualquiera con acceso al sistema de archivos.
///
/// El PIN NO se guarda jamás — ni aquí ni en ninguna parte del teléfono.
/// Lo único que persiste es el token que devolvió el servidor.
class SesionStorage {
  /// En flutter_secure_storage 11 el cifrado fuerte ya es el comportamiento
  /// por defecto en Android (AES-GCM con la clave envuelta en RSA-OAEP,
  /// respaldada por el Keystore), así que no hace falta configurarlo.
  SesionStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _claveSesion = 'sesion_actual';
  static const _claveUsuarioRecordado = 'usuario_recordado';
  static const _claveObraActiva = 'obra_activa';
  static const _clavePerfilTrabajador = 'perfil_trabajador';

  Future<void> guardar(SesionUsuario sesion) async {
    await _storage.write(key: _claveSesion, value: jsonEncode(sesion.aJson()));
    // Se recuerda por separado para poder ofrecer el acceso por PIN aunque
    // la sesión haya expirado o se haya cerrado.
    await _storage.write(
      key: _claveUsuarioRecordado,
      value: jsonEncode({
        'usuarioId': sesion.usuarioId,
        'nombre': sesion.nombre,
        'rol': sesion.rol,
      }),
    );
  }

  Future<SesionUsuario?> leer() async {
    final crudo = await _storage.read(key: _claveSesion);
    if (crudo == null) return null;
    try {
      return SesionUsuario.desdeJson(jsonDecode(crudo) as Map<String, dynamic>);
    } catch (_) {
      // Formato viejo o corrupto: se descarta y se pide login de nuevo.
      await _storage.delete(key: _claveSesion);
      return null;
    }
  }

  /// Borra la sesión y la credencial guardada; deja al usuario recordado
  /// para el acceso por PIN. Sin sesión la credencial no se puede mostrar, y
  /// así no queda en un teléfono que se presta o se entrega.
  Future<void> cerrarSesion() async {
    await _storage.delete(key: _claveSesion);
    await _storage.delete(key: _clavePerfilTrabajador);
  }

  /// Olvida también al usuario — "Cambiar" en la pantalla de PIN.
  Future<void> olvidarTodo() async {
    await _storage.delete(key: _claveSesion);
    await _storage.delete(key: _claveUsuarioRecordado);
    await _storage.delete(key: _claveObraActiva);
    await _storage.delete(key: _clavePerfilTrabajador);
  }

  Future<UsuarioRecordado?> leerUsuarioRecordado() async {
    final crudo = await _storage.read(key: _claveUsuarioRecordado);
    if (crudo == null) return null;
    try {
      final json = jsonDecode(crudo) as Map<String, dynamic>;
      return UsuarioRecordado(
        usuarioId: json['usuarioId'] as int,
        nombre: json['nombre'] as String,
        rol: json['rol'] as String,
      );
    } catch (_) {
      await _storage.delete(key: _claveUsuarioRecordado);
      return null;
    }
  }

  Future<String?> leerToken() async => (await leer())?.token;

  /// Obra en la que está trabajando quien usa el teléfono.
  ///
  /// El backend no asocia bodegueros a obras —solo los trabajadores tienen
  /// cuadrilla, y la cuadrilla tiene obra—, así que la elige la persona y el
  /// teléfono la recuerda. Sin esto habría que preguntarla en cada pantalla,
  /// y en una obra el bodeguero trabaja en una sola durante semanas.
  Future<void> guardarObraActiva(int obraId) =>
      _storage.write(key: _claveObraActiva, value: obraId.toString());

  Future<int?> leerObraActiva() async {
    final crudo = await _storage.read(key: _claveObraActiva);
    return crudo == null ? null : int.tryParse(crudo);
  }

  Future<void> olvidarObraActiva() => _storage.delete(key: _claveObraActiva);

  /// Última copia del perfil del trabajador, para mostrar su credencial sin
  /// conexión. Ver la nota en [PerfilTrabajador].
  Future<void> guardarPerfilTrabajador(PerfilTrabajador perfil) =>
      _storage.write(
        key: _clavePerfilTrabajador,
        value: jsonEncode({
          ...perfil.aJson(),
          'guardadoEl': DateTime.now().toIso8601String(),
        }),
      );

  /// La copia guardada, solo si es de [usuarioId]: en un teléfono compartido
  /// nadie ve la credencial de otro.
  Future<PerfilTrabajador?> leerPerfilTrabajador(int usuarioId) async {
    final crudo = await _storage.read(key: _clavePerfilTrabajador);
    if (crudo == null) return null;
    try {
      final perfil = PerfilTrabajador.desdeJson(
        jsonDecode(crudo) as Map<String, dynamic>,
      );
      return perfil.usuarioId == usuarioId ? perfil : null;
    } catch (_) {
      await _storage.delete(key: _clavePerfilTrabajador);
      return null;
    }
  }
}

/// Datos mínimos del último usuario que entró en este teléfono, para
/// ofrecerle el acceso rápido por PIN sin que escriba el correo.
class UsuarioRecordado {
  const UsuarioRecordado({
    required this.usuarioId,
    required this.nombre,
    required this.rol,
  });

  final int usuarioId;
  final String nombre;
  final String rol;
}
