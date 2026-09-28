import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/errores.dart';
import '../../core/network/idempotencia.dart';
import '../../core/theme/app_colors.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/obra.dart';
import '../../shared_widgets/campo_texto.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import '../../shared_widgets/presion.dart';
import '../../core/theme/app_theme.dart';
import '../../data/modelos/usuario.dart';
import '../obra/obra_activa.dart';
import 'pantalla_usuarios.dart';

/// Obras de la constructora. Crear y cerrar son exclusivas de ADMIN.
class PantallaObras extends ConsumerWidget {
  const PantallaObras({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final obras = ref.watch(todasLasObrasProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(todasLasObrasProvider.future),
        child: Contenido<List<Obra>>(
          valor: obras,
          alReintentar: () => ref.invalidate(todasLasObrasProvider),
          estaVacio: (l) => l.isEmpty,
          vacio: SingleChildScrollView(
            child: Vacio(
              icono: Icons.domain_outlined,
              titulo: 'Todavía no hay obras',
              detalle:
                  'La obra es el contenedor de todo lo demás: sin una obra no '
                  'se puede cubicar, presupuestar ni mover bodega.',
              accion: Builder(
                builder: (context) => FilledButton.icon(
                  onPressed: () => _abrirFormulario(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Crear la primera obra'),
                ),
              ),
            ),
          ),
          constructor: (lista) {
            final activas = lista.where((o) => o.activa).toList();
            final cerradas = lista.where((o) => !o.activa).toList();
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Etiqueta('Activas (${activas.length})'),
                const SizedBox(height: 8),
                for (final o in activas) ...[
                  _FilaObra(obra: o),
                  const SizedBox(height: 8),
                ],
                if (cerradas.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Etiqueta('Cerradas (${cerradas.length})'),
                  const SizedBox(height: 8),
                  for (final o in cerradas) ...[
                    _FilaObra(obra: o),
                    const SizedBox(height: 8),
                  ],
                ],
                const SizedBox(height: 80),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(context),
        backgroundColor: AppColors.accentFill,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Nueva obra'),
      ),
    );
  }

  static void _abrirFormulario(BuildContext context) =>
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const PantallaNuevaObra()));
}

class _FilaObra extends ConsumerStatefulWidget {
  const _FilaObra({required this.obra});

  final Obra obra;

  @override
  ConsumerState<_FilaObra> createState() => _FilaObraState();
}

class _FilaObraState extends ConsumerState<_FilaObra> {
  bool _enviando = false;
  final _intentoCierre = IntentoIdempotente();

  /// Solo un jefe de terreno o un admin puede dirigir una obra: el backend
  /// rechaza cualquier otro rol, así que la lista se filtra acá en vez de
  /// ofrecer opciones que van a fallar.
  Future<void> _elegirJefe(
    BuildContext context,
    WidgetRef ref,
    Obra obra,
  ) async {
    final candidatos = (ref.read(usuariosProvider).valueOrNull ?? const [])
        .where((u) => u.rol == 'JEFE_TERRENO' || u.rol == 'ADMIN')
        .toList();

    if (candidatos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No hay ningún usuario con rol Jefe de terreno o Administrador.',
          ),
        ),
      );
      return;
    }

    final elegido = await showModalBottomSheet<UsuarioEmpresa>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Jefe a cargo de ${obra.nombre}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: candidatos.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: AppColors.border),
                itemBuilder: (_, i) {
                  final u = candidatos[i];
                  return ListTile(
                    leading: Iniciales(u.nombre, tamano: 38),
                    title: Text(u.nombre),
                    subtitle: Text(
                      u.rut ?? 'sin RUT registrado',
                      style: TextStyle(
                        fontFamily: AppTheme.monoFamily,
                        fontSize: 12,
                        color: u.rut == null
                            ? AppColors.warningDark
                            : AppColors.secondary,
                      ),
                    ),
                    onTap: () => Navigator.of(context).pop(u),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (elegido == null) return;
    try {
      await ref.read(obrasApiProvider).asignarJefe(obra.id, elegido.id);
      ref.invalidate(todasLasObrasProvider);
      ref.invalidate(obrasActivasProvider);
      if (!context.mounted) return;
      // Sin esto el cambio pasaba en silencio: la fila se refresca un momento
      // después y no queda claro si el toque funcionó.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${elegido.nombre} queda a cargo de ${obra.nombre}'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensajeDeError(e))));
    }
  }

  /// Cerrar una obra congela su comparación entre presupuesto y consumo. El
  /// backend rechaza con 409 si quedan herramientas fuera o alertas sin
  /// resolver, así que el diálogo advierte, pero la última palabra es suya.
  Future<void> _cerrar() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Cerrar ${widget.obra.nombre}?'),
        content: const Text(
          'Después de cerrarla no se puede registrar más movimiento contra '
          'ella, y su desviación queda fijada. No se puede reabrir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.destructiveDark,
              minimumSize: const Size(0, 44),
            ),
            child: const Text('Cerrar obra'),
          ),
        ],
      ),
    );
    if (confirmado != true || _enviando) return;

    setState(() => _enviando = true);
    try {
      await ref
          .read(obrasApiProvider)
          .cerrar(
            widget.obra.id,
            clave: _intentoCierre.clavePara([widget.obra.id]),
          );
      ref.invalidate(todasLasObrasProvider);
      ref.invalidate(obrasActivasProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensajeDeError(e))));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.obra;
    return Panel(
      color: o.activa ? AppColors.card : AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  o.nombre,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              o.activa
                  ? ChipEstado.exito('Activa')
                  : ChipEstado.neutro('Cerrada'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            o.cliente,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 2),
          Text(
            o.ubicacion,
            style: const TextStyle(fontSize: 12, color: AppColors.secondary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.engineering_outlined,
                size: 17,
                color: o.tieneJefe
                    ? AppColors.secondary
                    : AppColors.warningDark,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  o.jefeIdentificacion,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: o.tieneJefe ? FontWeight.w500 : FontWeight.w400,
                    color: o.tieneJefe
                        ? AppColors.primary
                        : AppColors.warningDark,
                  ),
                ),
              ),
              if (o.activa)
                TextButton(
                  onPressed: () => _elegirJefe(context, ref, o),
                  child: Text(o.tieneJefe ? 'Cambiar' : 'Asignar'),
                ),
            ],
          ),
          if (o.activa) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _enviando ? null : _cerrar,
              icon: _enviando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.lock_outline, size: 18),
              label: Text(_enviando ? 'Cerrando…' : 'Cerrar obra'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                side: const BorderSide(color: AppColors.borderControl),
                foregroundColor: AppColors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PantallaNuevaObra extends ConsumerStatefulWidget {
  const PantallaNuevaObra({super.key});

  @override
  ConsumerState<PantallaNuevaObra> createState() => _PantallaNuevaObraState();
}

class _PantallaNuevaObraState extends ConsumerState<PantallaNuevaObra> {
  final _nombre = TextEditingController();
  final _cliente = TextEditingController();
  final _ubicacion = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _enviando = false;
  String? _error;
  final _intento = IntentoIdempotente();

  @override
  void dispose() {
    _nombre.dispose();
    _cliente.dispose();
    _ubicacion.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_enviando) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _enviando = true;
      _error = null;
    });
    final nombre = _nombre.text.trim();
    final cliente = _cliente.text.trim();
    final ubicacion = _ubicacion.text.trim();
    try {
      await ref
          .read(obrasApiProvider)
          .crear(
            nombre: nombre,
            cliente: cliente,
            ubicacion: ubicacion,
            clave: _intento.clavePara([nombre, cliente, ubicacion]),
          );
      ref.invalidate(todasLasObrasProvider);
      ref.invalidate(obrasActivasProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Obra creada')));
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva obra')),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CampoConEtiqueta(
                etiqueta: 'Nombre de la obra',
                campo: CampoTexto(
                  controlador: _nombre,
                  hint: 'Los Almendros · Torre B',
                  icono: Icons.domain_outlined,
                  habilitado: !_enviando,
                  validador: _obligatorio,
                ),
              ),
              const SizedBox(height: 16),
              CampoConEtiqueta(
                etiqueta: 'Cliente',
                campo: CampoTexto(
                  controlador: _cliente,
                  hint: 'Inmobiliaria Aconcagua',
                  icono: Icons.business_outlined,
                  habilitado: !_enviando,
                  validador: _obligatorio,
                ),
              ),
              const SizedBox(height: 16),
              CampoConEtiqueta(
                etiqueta: 'Ubicación',
                campo: CampoTexto(
                  controlador: _ubicacion,
                  hint: 'Av. Los Almendros 1240, Ñuñoa',
                  icono: Icons.place_outlined,
                  habilitado: !_enviando,
                  validador: _obligatorio,
                ),
                ayuda:
                    'Sirve para distinguir obras del mismo cliente en el '
                    'selector de bodega.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                MensajeError(mensaje: _error!),
              ],
              const SizedBox(height: 22),
              BotonEnvio(
                texto: 'Crear obra',
                textoEnviando: 'Creando…',
                enviando: _enviando,
                alPresionar: _guardar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String? _obligatorio(String? v) =>
    (v == null || v.trim().isEmpty) ? 'Este campo es obligatorio' : null;
