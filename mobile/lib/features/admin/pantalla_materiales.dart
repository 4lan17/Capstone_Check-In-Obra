import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formato.dart';
import '../../core/network/errores.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/material.dart';
import '../../shared_widgets/campo_texto.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import '../bodega/bodega_providers.dart';
import '../bodega/pantalla_bodega.dart';

/// Categorías de `CategoriaMaterial`. El rubro es tabiquería y cielos, así que
/// son estas cuatro y no un campo libre.
const categorias = ['METALCOM', 'VOLCANITA', 'OSB', 'FIJACION'];

/// Catálogo de materiales de la empresa: precio unitario, stock mínimo y
/// merma. Es lo que alimenta la cubicación y el presupuesto, así que un precio
/// mal cargado se propaga a toda la obra.
class PantallaMateriales extends ConsumerWidget {
  const PantallaMateriales({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogo = ref.watch(catalogoProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(catalogoProvider.future),
        child: Contenido<List<MaterialObra>>(
          valor: catalogo,
          alReintentar: () => ref.invalidate(catalogoProvider),
          estaVacio: (l) => l.isEmpty,
          vacio: SingleChildScrollView(
            child: Vacio(
              icono: Icons.category_outlined,
              titulo: 'El catálogo está vacío',
              detalle:
                  'Sin materiales no se puede cubicar ni mover bodega. '
                  'Empieza por los que más se usan en la obra.',
              accion: Builder(
                builder: (context) => FilledButton.icon(
                  onPressed: () => _nuevo(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar material'),
                ),
              ),
            ),
          ),
          constructor: (lista) {
            final porCategoria = <String, List<MaterialObra>>{};
            for (final m in lista) {
              porCategoria.putIfAbsent(m.categoria, () => []).add(m);
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final categoria in categorias)
                  if (porCategoria[categoria] case final materiales?) ...[
                    Etiqueta('$categoria · ${materiales.length}'),
                    const SizedBox(height: 8),
                    for (final m in materiales) ...[
                      _FilaMaterial(material: m),
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
        onPressed: () => _nuevo(context),
        backgroundColor: AppColors.accentFill,
        foregroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo material'),
      ),
    );
  }

  static void _nuevo(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const PantallaNuevoMaterial()));
}

class _FilaMaterial extends ConsumerWidget {
  const _FilaMaterial({required this.material});

  final MaterialObra material;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unidad = unidadDe(material.categoria);
    return PanelTocable(
      semanticLabel:
          '${material.nombre}, ${Formato.pesos(material.precioUnitario)} '
          'por $unidad. Tocar para editar precio y merma',
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _HojaEdicion(material: material),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  material.nombre,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${material.sku} · mín. ${Formato.cantidad(material.stockMinimo)} $unidad',
                  style: const TextStyle(
                    fontFamily: AppTheme.monoFamily,
                    fontSize: 11.5,
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            Formato.pesos(material.precioUnitario),
            style: const TextStyle(
              fontFamily: AppTheme.monoFamily,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Precio y merma se editan juntos porque son las dos cosas que cambian de un
/// material ya creado: el SKU y el nombre no se tocan, y el stock mínimo se
/// define al darlo de alta.
class _HojaEdicion extends ConsumerStatefulWidget {
  const _HojaEdicion({required this.material});

  final MaterialObra material;

  @override
  ConsumerState<_HojaEdicion> createState() => _HojaEdicionState();
}

class _HojaEdicionState extends ConsumerState<_HojaEdicion> {
  late final _precio = TextEditingController(
    text: widget.material.precioUnitario.toStringAsFixed(0),
  );
  final _merma = TextEditingController();
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _precio.dispose();
    _merma.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final api = ref.read(materialesApiProvider);

      final precio = double.tryParse(_precio.text.replaceAll('.', ''));
      if (precio != null && precio != widget.material.precioUnitario) {
        await api.actualizarPrecio(widget.material.id, precio);
      }

      final merma = double.tryParse(_merma.text.replaceAll(',', '.'));
      if (merma != null) {
        await api.definirMerma(widget.material.id, merma);
      }

      ref.invalidate(catalogoProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Material actualizado')));
    } catch (e) {
      setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.material.nombre,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 18),
              CampoConEtiqueta(
                etiqueta: 'Precio unitario',
                campo: CampoTexto(
                  controlador: _precio,
                  hint: '5980',
                  icono: Icons.attach_money,
                  mono: true,
                  teclado: TextInputType.number,
                  formatters: [FilteringTextInputFormatter.digitsOnly],
                  habilitado: !_enviando,
                ),
                ayuda:
                    'Alimenta el presupuesto. Cambiarlo no altera los '
                    'presupuestos ya congelados.',
              ),
              const SizedBox(height: 16),
              CampoConEtiqueta(
                etiqueta: 'Merma parametrizada (%)',
                campo: CampoTexto(
                  controlador: _merma,
                  hint: '12',
                  icono: Icons.content_cut,
                  mono: true,
                  teclado: const TextInputType.numberWithOptions(decimal: true),
                  formatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  habilitado: !_enviando,
                ),
                ayuda:
                    'Lo que el motor de cubicación agrega sobre la cantidad '
                    'calculada. Déjalo en blanco para no modificarlo.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                MensajeError(mensaje: _error!),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _enviando ? null : _guardar,
                child: Text(_enviando ? 'Guardando…' : 'Guardar cambios'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class PantallaNuevoMaterial extends ConsumerStatefulWidget {
  const PantallaNuevoMaterial({super.key});

  @override
  ConsumerState<PantallaNuevoMaterial> createState() =>
      _PantallaNuevoMaterialState();
}

class _PantallaNuevoMaterialState extends ConsumerState<PantallaNuevoMaterial> {
  final _sku = TextEditingController();
  final _nombre = TextEditingController();
  final _precio = TextEditingController();
  final _minimo = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _categoria = categorias.first;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _sku.dispose();
    _nombre.dispose();
    _precio.dispose();
    _minimo.dispose();
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
          .read(materialesApiProvider)
          .crear(
            sku: _sku.text.trim().toUpperCase(),
            nombre: _nombre.text.trim(),
            categoria: _categoria,
            precioUnitario: double.parse(_precio.text.replaceAll('.', '')),
            stockMinimo: double.parse(_minimo.text.replaceAll(',', '.')),
          );
      ref.invalidate(catalogoProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Material agregado')));
    } catch (e) {
      setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo material')),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CampoConEtiqueta(
                etiqueta: 'SKU',
                campo: CampoTexto(
                  controlador: _sku,
                  hint: 'VOL-ST-10-120240',
                  icono: Icons.qr_code_2,
                  mono: true,
                  habilitado: !_enviando,
                  validador: (v) => (v == null || v.trim().isEmpty)
                      ? 'El SKU identifica al material y es obligatorio'
                      : null,
                ),
                ayuda: 'Único en la empresa. Es lo que viene en la guía de despacho.',
              ),
              const SizedBox(height: 16),
              CampoConEtiqueta(
                etiqueta: 'Nombre',
                campo: CampoTexto(
                  controlador: _nombre,
                  hint: 'Volcanita ST 10 mm · 1,20 × 2,40',
                  icono: Icons.label_outline,
                  habilitado: !_enviando,
                  validador: (v) => (v == null || v.trim().isEmpty)
                      ? 'Este campo es obligatorio'
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              const Etiqueta('Categoría'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in categorias)
                    _ChipCategoria(
                      categoria: c,
                      activa: _categoria == c,
                      onTap: _enviando
                          ? null
                          : () => setState(() => _categoria = c),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              CampoConEtiqueta(
                etiqueta: 'Precio unitario',
                campo: CampoTexto(
                  controlador: _precio,
                  hint: '5980',
                  icono: Icons.attach_money,
                  mono: true,
                  teclado: TextInputType.number,
                  formatters: [FilteringTextInputFormatter.digitsOnly],
                  habilitado: !_enviando,
                  validador: (v) => double.tryParse(v ?? '') == null
                      ? 'Escribe el precio'
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              CampoConEtiqueta(
                etiqueta: 'Stock mínimo de obra',
                campo: CampoTexto(
                  controlador: _minimo,
                  hint: '40',
                  icono: Icons.warning_amber_outlined,
                  mono: true,
                  teclado: const TextInputType.numberWithOptions(decimal: true),
                  formatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  habilitado: !_enviando,
                  validador: (v) =>
                      double.tryParse((v ?? '').replaceAll(',', '.')) == null
                      ? 'Escribe el mínimo'
                      : null,
                ),
                ayuda:
                    'Bajo esta cantidad se genera una alerta de stock crítico '
                    'en la obra.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                MensajeError(mensaje: _error!),
              ],
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _enviando ? null : _guardar,
                child: Text(_enviando ? 'Guardando…' : 'Agregar al catálogo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipCategoria extends StatelessWidget {
  const _ChipCategoria({
    required this.categoria,
    required this.activa,
    required this.onTap,
  });

  final String categoria;
  final bool activa;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: activa,
      label: categoria,
      excludeSemantics: true,
      child: Material(
        color: activa ? AppColors.primary : AppColors.card,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              border: Border.fromBorderSide(
                BorderSide(
                  color: activa ? AppColors.primary : AppColors.borderControl,
                ),
              ),
            ),
            child: Text(
              categoria,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: activa ? Colors.white : AppColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
