import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/errores.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_forma.dart';
import '../../data/api/auth_api.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/material.dart';
import '../../shared_widgets/campo_texto.dart';
import '../../shared_widgets/estados.dart';

/// Lo que se busca, sin los espacios que se cuelan al teclear o al pegar:
/// `" 780 1234 567890 "` es el mismo código que `"7801234567890"`. Las
/// mayúsculas las resuelve el servidor, que busca el SKU sin distinguirlas.
String codigoNormalizado(String texto) => texto.replaceAll(RegExp(r'\s+'), '');

/// Busca un material por su SKU o por su código de barras, sin recorrer el
/// catálogo: es la misma consulta que usa el escáner de bodega
/// (`GET /api/materiales/por-codigo/{codigo}`).
///
/// Quien lo usa decide cómo se dibuja el material hallado ([filaDe]): así la
/// fila es idéntica a la del catálogo y abre lo mismo al tocarla.
class BuscadorMaterial extends ConsumerStatefulWidget {
  const BuscadorMaterial({super.key, required this.filaDe});

  final Widget Function(MaterialObra material) filaDe;

  @override
  ConsumerState<BuscadorMaterial> createState() => _BuscadorMaterialState();
}

/// Qué hay debajo del campo.
sealed class _Busqueda {
  const _Busqueda();
}

class _Buscando extends _Busqueda {
  const _Buscando();
}

class _Hallado extends _Busqueda {
  const _Hallado(this.material);
  final MaterialObra material;
}

class _NoHay extends _Busqueda {
  const _NoHay();
}

class _Fallo extends _Busqueda {
  const _Fallo(this.mensaje);
  final String mensaje;
}

class _BuscadorMaterialState extends ConsumerState<BuscadorMaterial> {
  final _controlador = TextEditingController();
  _Busqueda? _estado;

  /// Una respuesta que llega después de que se cambió el texto no vale: sin
  /// esto, el resultado de la búsqueda anterior pisa al de la actual.
  int _turno = 0;

  @override
  void initState() {
    super.initState();
    _controlador.addListener(_alCambiarTexto);
  }

  @override
  void dispose() {
    _controlador
      ..removeListener(_alCambiarTexto)
      ..dispose();
    super.dispose();
  }

  String _ultimoTexto = '';

  void _alCambiarTexto() {
    // El listener también salta con cada movimiento del cursor: solo importa
    // si el texto cambió de verdad.
    if (_controlador.text == _ultimoTexto) return;
    _ultimoTexto = _controlador.text;
    _turno++;
    setState(() => _estado = null);
  }

  Future<void> _buscar(String texto) async {
    final codigo = codigoNormalizado(texto);
    if (codigo.isEmpty) return;
    FocusScope.of(context).unfocus();
    final turno = ++_turno;
    setState(() => _estado = const _Buscando());
    _Busqueda resultado;
    try {
      resultado = _Hallado(
        await ref.read(materialesApiProvider).porCodigo(codigo),
      );
    } on ApiException catch (e) {
      resultado = e.statusCode == 404
          ? const _NoHay()
          : _Fallo(mensajeDeError(e));
    } catch (e) {
      resultado = _Fallo(mensajeDeError(e));
    }
    if (!mounted || turno != _turno) return;
    setState(() => _estado = resultado);
  }

  void _limpiar() {
    _controlador.clear();
    // `clear` ya dispara el listener, que descarta el resultado.
  }

  @override
  Widget build(BuildContext context) {
    final estado = _estado;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'Buscar por SKU o código de barras',
          textField: true,
          child: CampoTexto(
            key: const ValueKey('buscador'),
            controlador: _controlador,
            hint: 'Buscar por SKU o código de barras',
            icono: Icons.search,
            mono: true,
            teclado: TextInputType.visiblePassword,
            sufijo: _controlador.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpiar la búsqueda',
                    icon: const Icon(
                      Icons.close,
                      size: 20,
                      color: AppColors.secondary,
                    ),
                    onPressed: _limpiar,
                  ),
            alEnviar: _buscar,
          ),
        ),
        if (estado != null) ...[
          const SizedBox(height: AppEspacio.sm + 4),
          switch (estado) {
            _Buscando() => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppEspacio.md),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.accentFill),
              ),
            ),
            _Hallado(:final material) => KeyedSubtree(
              key: const ValueKey('resultado-busqueda'),
              child: widget.filaDe(material),
            ),
            _NoHay() => const Vacio(
              icono: Icons.search_off,
              titulo: 'No hay un material con ese código o SKU',
              detalle:
                  'Revisa que esté bien escrito. Si el material es nuevo, '
                  'agrégalo al catálogo.',
            ),
            _Fallo(:final mensaje) => MensajeError(mensaje: mensaje),
          },
        ],
        const SizedBox(height: AppEspacio.md),
      ],
    );
  }
}
