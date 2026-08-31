import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/errores.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/usuario.dart';
import '../../shared_widgets/campo_texto.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import '../auth/sesion_controller.dart';

final usuariosProvider = FutureProvider<List<UsuarioEmpresa>>(
  (ref) => ref.watch(usuariosApiProvider).listar(),
);

/// Usuarios de la constructora y su rol.
///
/// Un usuario tiene un solo rol, y ese rol vale para todas las obras de la
/// empresa: el backend lo resuelve con una sola clase `Usuario` y un enum, no
/// con una subclase por rol.
class PantallaUsuarios extends ConsumerWidget {
  const PantallaUsuarios({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usuarios = ref.watch(usuariosProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(usuariosProvider.future),
        child: Contenido<List<UsuarioEmpresa>>(
          valor: usuarios,
          alReintentar: () => ref.invalidate(usuariosProvider),
          constructor: (lista) {
            const orden = ['ADMIN', 'JEFE_TERRENO', 'BODEGUERO', 'TRABAJADOR'];
            final porRol = <String, List<UsuarioEmpresa>>{};
            for (final u in lista) {
              porRol.putIfAbsent(u.rol, () => []).add(u);
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final rol in orden)
                  if (porRol[rol] case final delRol?) ...[
                    Etiqueta('${nombreDeRol(rol)} · ${delRol.length}'),
                    const SizedBox(height: 8),
                    for (final u in delRol) ...[
                      _FilaUsuario(usuario: u),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 12),
                  ],
                const SizedBox(height: 70),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const PantallaNuevoUsuario())),
        backgroundColor: AppColors.accentFill,
        foregroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Nuevo usuario'),
      ),
    );
  }
}

class _FilaUsuario extends ConsumerStatefulWidget {
  const _FilaUsuario({required this.usuario});

  final UsuarioEmpresa usuario;

  @override
  ConsumerState<_FilaUsuario> createState() => _FilaUsuarioState();
}

class _FilaUsuarioState extends ConsumerState<_FilaUsuario> {
  /// Restablecer el PIN es la única operación de mantenimiento que existe:
  /// el PIN no se puede consultar —solo se guarda su hash— así que cuando
  /// alguien lo olvida, no hay nada que recuperar, solo que reemplazar.
  Future<void> _restablecerPin() async {
    final controlador = TextEditingController();
    final nuevo = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text('PIN de ${widget.usuario.nombre}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'El PIN anterior no se puede recuperar: el sistema solo guarda '
              'su huella. Define uno nuevo y entrégaselo en persona.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            CampoTexto(
              controlador: controlador,
              hint: '••••',
              icono: Icons.lock_outline,
              mono: true,
              maxLength: 4,
              teclado: TextInputType.number,
              formatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controlador.text),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Restablecer'),
          ),
        ],
      ),
    );
    controlador.dispose();

    if (nuevo == null || nuevo.length != 4) return;
    try {
      await ref
          .read(usuariosApiProvider)
          .redefinirPin(widget.usuario.id, nuevo);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('PIN restablecido')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensajeDeError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.usuario;
    return Panel(
      child: Row(
        children: [
          Iniciales(u.nombre, tamano: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  u.nombre,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  u.rut ?? 'sin RUT registrado',
                  style: TextStyle(
                    fontFamily: AppTheme.monoFamily,
                    fontSize: 12,
                    color: u.rut == null
                        ? AppColors.warningDark
                        : AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  u.email,
                  style: const TextStyle(
                    fontFamily: AppTheme.monoFamily,
                    fontSize: 11,
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Restablecer el PIN de ${u.nombre}',
            icon: const Icon(Icons.lock_reset, color: AppColors.secondary),
            onPressed: _restablecerPin,
          ),
        ],
      ),
    );
  }
}

class PantallaNuevoUsuario extends ConsumerStatefulWidget {
  const PantallaNuevoUsuario({super.key});

  @override
  ConsumerState<PantallaNuevoUsuario> createState() =>
      _PantallaNuevoUsuarioState();
}

class _PantallaNuevoUsuarioState extends ConsumerState<PantallaNuevoUsuario> {
  final _nombre = TextEditingController();
  final _email = TextEditingController();
  final _rut = TextEditingController();
  final _pin = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _rol = 'BODEGUERO';
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _email.dispose();
    _rut.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      await ref
          .read(usuariosApiProvider)
          .crear(
            nombre: _nombre.text.trim(),
            email: _email.text.trim(),
            rut: _rut.text.trim(),
            rol: _rol,
            pinInicial: _pin.text,
          );
      ref.invalidate(usuariosProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Usuario registrado')));
    } catch (e) {
      setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo usuario')),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CampoConEtiqueta(
                etiqueta: 'Nombre completo',
                campo: CampoTexto(
                  controlador: _nombre,
                  hint: 'Nicolás Bravo Herrera',
                  icono: Icons.person_outline,
                  habilitado: !_enviando,
                  validador: (v) => (v == null || v.trim().isEmpty)
                      ? 'Este campo es obligatorio'
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              CampoConEtiqueta(
                etiqueta: 'Correo de empresa',
                campo: CampoTexto(
                  controlador: _email,
                  hint: 'nombre@empresa.cl',
                  icono: Icons.mail_outline,
                  mono: true,
                  teclado: TextInputType.emailAddress,
                  habilitado: !_enviando,
                  validador: (v) => (v == null || !v.contains('@'))
                      ? 'Escribe un correo válido'
                      : null,
                ),
                ayuda:
                    'Identifica al usuario y es único en el sistema. El '
                    'trabajador no lo escribe: entra con PIN.',
              ),
              const SizedBox(height: 16),
              CampoConEtiqueta(
                etiqueta: 'RUT',
                campo: CampoTexto(
                  controlador: _rut,
                  hint: '17.930.556-4',
                  icono: Icons.badge_outlined,
                  mono: true,
                  habilitado: !_enviando,
                  validador: (v) => (v == null || v.trim().isEmpty)
                      ? 'El RUT es obligatorio'
                      : null,
                ),
                ayuda:
                    'Identifica a la persona en toda la cadena: quien recibe un '
                    'despacho, quien tiene una herramienta y quien dirige una '
                    'obra se muestran por nombre y RUT.',
              ),
              const SizedBox(height: 18),
              const Etiqueta('Rol'),
              const SizedBox(height: 8),
              for (final rol in const [
                'BODEGUERO',
                'JEFE_TERRENO',
                'ADMIN',
                'TRABAJADOR',
              ]) ...[
                _OpcionRol(
                  rol: rol,
                  activa: _rol == rol,
                  onTap: _enviando ? null : () => setState(() => _rol = rol),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 10),
              CampoConEtiqueta(
                etiqueta: 'PIN inicial',
                campo: CampoTexto(
                  controlador: _pin,
                  hint: '••••',
                  icono: Icons.lock_outline,
                  mono: true,
                  oculto: true,
                  maxLength: 4,
                  teclado: TextInputType.number,
                  formatters: [FilteringTextInputFormatter.digitsOnly],
                  habilitado: !_enviando,
                  validador: (v) => (v == null || v.length != 4)
                      ? 'El PIN son 4 dígitos'
                      : null,
                ),
                ayuda:
                    'Entrégaselo en persona y pídele que lo cambie. El sistema '
                    'guarda solo su huella: ni tú ni nadie puede volver a verlo.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                MensajeError(mensaje: _error!),
              ],
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _enviando ? null : _guardar,
                child: Text(_enviando ? 'Registrando…' : 'Registrar usuario'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpcionRol extends StatelessWidget {
  const _OpcionRol({
    required this.rol,
    required this.activa,
    required this.onTap,
  });

  final String rol;
  final bool activa;
  final VoidCallback? onTap;

  /// Lo que habilita cada rol, tomado de la matriz de permisos del README.
  static String _queHace(String rol) => switch (rol) {
    'BODEGUERO' =>
      'App de terreno: kardex, préstamos, devoluciones y cierre de turno.',
    'JEFE_TERRENO' => 'Cubicación, presupuesto y desviación de su obra.',
    'ADMIN' => 'Todo lo anterior, más usuarios, catálogo, mermas y obras.',
    _ => 'Pide herramienta y material, y muestra su credencial QR.',
  };

  @override
  Widget build(BuildContext context) {
    return PanelTocable(
      semanticLabel: '${nombreDeRol(rol)}. ${_queHace(rol)}',
      onTap: onTap,
      color: activa ? AppColors.warningTint : AppColors.card,
      borderColor: activa ? AppColors.accentFill : AppColors.borderControl,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            activa ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 20,
            color: activa ? AppColors.accentFill : AppColors.secondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombreDeRol(rol),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _queHace(rol),
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
