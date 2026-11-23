import 'package:checkinobra_mobile/core/sin_reintentos.dart';
import 'package:checkinobra_mobile/core/theme/app_theme.dart';
import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/data/api/dominio_api.dart';
import 'package:checkinobra_mobile/data/modelos/material.dart';
import 'package:checkinobra_mobile/features/admin/buscador_material.dart';
import 'package:checkinobra_mobile/features/admin/pantalla_materiales.dart';
import 'package:checkinobra_mobile/features/bodega/bodega_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'fuentes.dart';

const _volcanita = MaterialObra(
  id: 2,
  sku: 'VOL-ST-10',
  codigoBarra: '7801234567890',
  nombre: 'Volcanita ST 10 mm',
  categoria: 'VOLCANITA',
  precioUnitario: 5980,
  stockMinimo: 40,
);

const _tornillo = MaterialObra(
  id: 3,
  sku: 'TOR-6',
  codigoBarra: null,
  nombre: 'Tornillo punta broca',
  categoria: 'FIJACION',
  precioUnitario: 3000,
  stockMinimo: 10,
);

/// Busca como el backend: por código de barras exacto o por SKU en
/// mayúsculas, y responde 404 si no hay.
class _MaterialesFalsos implements MaterialesApi {
  final pedidos = <String>[];
  Object? falla;

  @override
  Future<MaterialObra> porCodigo(String codigo) async {
    pedidos.add(codigo);
    if (falla != null) throw falla!;
    for (final m in [_volcanita, _tornillo]) {
      if (m.codigoBarra == codigo || m.sku == codigo.toUpperCase()) return m;
    }
    throw const ApiException(404, 'Código no reconocido');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_MaterialesFalsos> _montar(
  WidgetTester tester, {
  _MaterialesFalsos? api,
}) async {
  final falsos = api ?? _MaterialesFalsos();
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: sinReintentos,
      overrides: [
        materialesApiProvider.overrideWithValue(falsos),
        catalogoProvider.overrideWith((ref) async => [_volcanita, _tornillo]),
        faltantesProvider.overrideWith((ref) async => const []),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 780),
            textScaler: TextScaler.linear(1.3),
          ),
          child: const PantallaMateriales(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return falsos;
}

Future<void> _buscar(WidgetTester tester, String texto) async {
  await tester.enterText(find.byKey(const ValueKey('buscador')), texto);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

Finder get _resultado => find.byKey(const ValueKey('resultado-busqueda'));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_CL');
    await cargarInter();
  });

  group('Normalización', () {
    test('quita los espacios de los bordes y de adentro', () {
      expect(codigoNormalizado('  VOL-ST-10 '), 'VOL-ST-10');
      expect(codigoNormalizado('780 1234 567890'), '7801234567890');
      expect(codigoNormalizado('\tVOL ST 10\n'), 'VOLST10');
    });

    test('lo que queda vacío no es un código', () {
      expect(codigoNormalizado('   '), isEmpty);
    });
  });

  group('Administrador › Materiales › buscador', () {
    testWidgets('el catálogo trae el campo de búsqueda', (tester) async {
      await _montar(tester);

      expect(find.byKey(const ValueKey('buscador')), findsOneWidget);
      expect(find.text('Buscar por SKU o código de barras'), findsOneWidget);
    });

    testWidgets('un SKU que existe muestra el material y lo abre al tocarlo', (
      tester,
    ) async {
      final api = await _montar(tester);

      await _buscar(tester, 'VOL-ST-10');

      expect(api.pedidos, ['VOL-ST-10']);
      expect(
        find.descendant(
          of: _resultado,
          matching: find.text('Volcanita ST 10 mm'),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(
          of: _resultado,
          matching: find.text('Volcanita ST 10 mm'),
        ),
      );
      await tester.pumpAndSettle();

      // Es la misma hoja que abre la fila del catálogo: precio y merma.
      expect(find.text('Guardar cambios'), findsOneWidget);
    });

    testWidgets('un código de barras también lo encuentra', (tester) async {
      await _montar(tester);

      await _buscar(tester, '7801234567890');

      expect(
        find.descendant(
          of: _resultado,
          matching: find.text('Volcanita ST 10 mm'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('no distingue mayúsculas ni espacios', (tester) async {
      final api = await _montar(tester);

      await _buscar(tester, '  vol-st-10  ');

      expect(api.pedidos, ['vol-st-10']);
      expect(
        find.descendant(
          of: _resultado,
          matching: find.text('Volcanita ST 10 mm'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('un código de barras con espacios se pega sin ellos', (
      tester,
    ) async {
      final api = await _montar(tester);

      await _buscar(tester, '780 1234 567890');

      expect(api.pedidos, ['7801234567890']);
    });

    testWidgets('un código que no existe (404) lo dice con claridad', (
      tester,
    ) async {
      await _montar(tester);

      await _buscar(tester, 'NO-EXISTE');

      expect(
        find.text('No hay un material con ese código o SKU'),
        findsOneWidget,
      );
      expect(_resultado, findsNothing);
    });

    testWidgets('otro error del servidor se muestra tal cual, no como '
        '"no existe"', (tester) async {
      final api = _MaterialesFalsos()
        ..falla = const ApiException(500, 'No pudimos buscar. Reintenta.');
      await _montar(tester, api: api);

      await _buscar(tester, 'VOL-ST-10');

      expect(find.text('No pudimos buscar. Reintenta.'), findsOneWidget);
      expect(
        find.text('No hay un material con ese código o SKU'),
        findsNothing,
      );
    });

    testWidgets('un campo vacío no llama al servidor', (tester) async {
      final api = await _montar(tester);

      await _buscar(tester, '   ');

      expect(api.pedidos, isEmpty);
      expect(
        find.text('No hay un material con ese código o SKU'),
        findsNothing,
      );
    });

    testWidgets('limpiar el campo borra el resultado y el aviso', (
      tester,
    ) async {
      await _montar(tester);
      await _buscar(tester, 'NO-EXISTE');
      expect(
        find.text('No hay un material con ese código o SKU'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Limpiar la búsqueda'));
      await tester.pumpAndSettle();

      expect(
        find.text('No hay un material con ese código o SKU'),
        findsNothing,
      );
      expect(find.byTooltip('Limpiar la búsqueda'), findsNothing);
    });

    testWidgets('cambiar el texto descarta el resultado anterior', (
      tester,
    ) async {
      await _montar(tester);
      await _buscar(tester, 'VOL-ST-10');
      expect(_resultado, findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('buscador')), 'VOL-');
      await tester.pumpAndSettle();

      expect(_resultado, findsNothing);
    });

    testWidgets('el catálogo sigue ahí debajo de la búsqueda', (tester) async {
      await _montar(tester);
      await _buscar(tester, 'VOL-ST-10');

      expect(find.text('Tornillo punta broca'), findsOneWidget);
    });
  });
}
