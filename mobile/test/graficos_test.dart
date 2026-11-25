import 'package:checkinobra_mobile/core/theme/app_theme.dart';
import 'package:checkinobra_mobile/shared_widgets/graficos/colores_grafico.dart';
import 'package:checkinobra_mobile/shared_widgets/graficos/grafico_barras.dart';
import 'package:checkinobra_mobile/shared_widgets/graficos/grafico_dona.dart';
import 'package:checkinobra_mobile/shared_widgets/graficos/grafico_linea.dart';
import 'package:checkinobra_mobile/shared_widgets/graficos/grafico_vacio.dart';
import 'package:checkinobra_mobile/shared_widgets/graficos/tarjeta_metrica.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fuentes.dart';

Future<void> _montar(
  WidgetTester tester,
  Widget grafico, {
  double escala = 1.3,
}) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 900),
          textScaler: TextScaler.linear(escala),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: grafico,
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(() async {
    await cargarInter();
  });

  group('Gráfico de líneas', () {
    final gasto = SerieLinea(
      nombre: 'Ejecutado acumulado',
      valores: const [8, 21, 52.3],
      color: ColoresGrafico.ejecutado,
      conArea: true,
    );
    final presupuesto = SerieLinea(
      nombre: 'Presupuesto',
      valores: const [48.2, 48.2, 48.2],
      color: ColoresGrafico.referencia,
      punteada: true,
    );

    testWidgets('dibuja cada serie con sus puntos', (tester) async {
      await _montar(
        tester,
        GraficoLinea(
          etiquetasX: const ['S1', 'S2', 'S3'],
          series: [gasto, presupuesto],
          descripcion: 'Gasto acumulado',
        ),
      );

      final datos = tester.widget<LineChart>(find.byType(LineChart)).data;
      expect(datos.lineBarsData, hasLength(2));
      expect(datos.lineBarsData[0].spots.map((s) => s.y), [8, 21, 52.3]);
      expect(datos.lineBarsData[1].spots, hasLength(3));
    });

    testWidgets('la serie de referencia va punteada y la principal sólida', (
      tester,
    ) async {
      await _montar(
        tester,
        GraficoLinea(
          etiquetasX: const ['S1', 'S2', 'S3'],
          series: [gasto, presupuesto],
          descripcion: 'Gasto acumulado',
        ),
      );

      final barras = tester
          .widget<LineChart>(find.byType(LineChart))
          .data
          .lineBarsData;
      expect(barras[0].dashArray, isNull);
      expect(barras[1].dashArray, isNotNull);
      expect(barras[0].color, ColoresGrafico.ejecutado);
      expect(barras[1].color, ColoresGrafico.referencia);
    });

    testWidgets('la serie principal lleva un área suave debajo', (
      tester,
    ) async {
      await _montar(
        tester,
        GraficoLinea(
          etiquetasX: const ['S1', 'S2', 'S3'],
          series: [gasto, presupuesto],
          descripcion: 'Gasto acumulado',
        ),
      );

      final barras = tester
          .widget<LineChart>(find.byType(LineChart))
          .data
          .lineBarsData;
      expect(barras[0].belowBarData.show, isTrue);
      expect(barras[1].belowBarData.show, isFalse);
    });

    testWidgets('muestra las etiquetas del eje horizontal', (tester) async {
      await _montar(
        tester,
        GraficoLinea(
          etiquetasX: const ['S1', 'S2', 'S3'],
          series: [gasto],
          descripcion: 'Gasto acumulado',
        ),
      );

      for (final e in ['S1', 'S2', 'S3']) {
        expect(find.text(e), findsOneWidget);
      }
    });

    testWidgets('el eje vertical parte de cero', (tester) async {
      await _montar(
        tester,
        GraficoLinea(
          etiquetasX: const ['S1', 'S2', 'S3'],
          series: [gasto],
          descripcion: 'Gasto acumulado',
        ),
      );

      expect(tester.widget<LineChart>(find.byType(LineChart)).data.minY, 0);
    });

    testWidgets('el eje vertical cubre también a la referencia', (
      tester,
    ) async {
      await _montar(
        tester,
        GraficoLinea(
          etiquetasX: const ['S1', 'S2'],
          series: [
            SerieLinea(
              nombre: 'a',
              valores: const [1, 2],
              color: ColoresGrafico.ejecutado,
            ),
            SerieLinea(
              nombre: 'ref',
              valores: const [90, 90],
              color: ColoresGrafico.referencia,
              punteada: true,
            ),
          ],
          descripcion: 'x',
        ),
      );

      expect(
        tester.widget<LineChart>(find.byType(LineChart)).data.maxY,
        greaterThanOrEqualTo(90),
      );
    });

    testWidgets('marca el último punto en rojo y lo dice con texto', (
      tester,
    ) async {
      await _montar(
        tester,
        GraficoLinea(
          etiquetasX: const ['S1', 'S2', 'S3'],
          series: [gasto, presupuesto],
          descripcion: 'Gasto acumulado',
          marcaFinal: 'Supera el presupuesto',
        ),
      );

      // Color + texto: el rojo solo no lo ve quien no distingue colores.
      expect(find.text('Supera el presupuesto'), findsOneWidget);
    });

    testWidgets('sin marca, no dice nada de más', (tester) async {
      await _montar(
        tester,
        GraficoLinea(
          etiquetasX: const ['S1', 'S2', 'S3'],
          series: [gasto, presupuesto],
          descripcion: 'Gasto acumulado',
        ),
      );

      expect(find.text('Supera el presupuesto'), findsNothing);
    });

    testWidgets('con una sola serie y un solo punto no se rompe', (
      tester,
    ) async {
      await _montar(
        tester,
        GraficoLinea(
          etiquetasX: const ['S1'],
          series: [
            SerieLinea(
              nombre: 'a',
              valores: const [5],
              color: ColoresGrafico.ejecutado,
            ),
          ],
          descripcion: 'x',
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(LineChart), findsOneWidget);
    });

    testWidgets('con muchas etiquetas no las apila: muestra solo algunas', (
      tester,
    ) async {
      final etiquetas = [for (var i = 1; i <= 30; i++) '$i'];
      await _montar(
        tester,
        GraficoLinea(
          etiquetasX: etiquetas,
          series: [
            SerieLinea(
              nombre: 'a',
              valores: [for (var i = 0; i < 30; i++) i.toDouble()],
              color: ColoresGrafico.ejecutado,
            ),
          ],
          descripcion: 'x',
        ),
      );

      final visibles = etiquetas.where(
        (e) => find.text(e).evaluate().isNotEmpty,
      );
      expect(visibles.length, lessThan(15));
      expect(visibles, isNotEmpty);
    });

    testWidgets('se anuncia como un solo gráfico, con su descripción', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _montar(
        tester,
        GraficoLinea(
          etiquetasX: const ['S1', 'S2', 'S3'],
          series: [gasto, presupuesto],
          descripcion:
              'Gasto acumulado: de 8 a 52,3 millones; presupuesto 48,2',
        ),
      );

      expect(
        find.bySemanticsLabel(
          'Gráfico de líneas. Gasto acumulado: de 8 a 52,3 millones; presupuesto 48,2',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('Barras agrupadas', () {
    final grupos = [
      GrupoDeBarras(
        etiqueta: 'Volcanita ST',
        barras: const [
          BarraDeGrupo(
            valor: 100,
            color: ColoresGrafico.presupuesto,
            texto: '\$11,8 M',
          ),
          BarraDeGrupo(
            valor: 150,
            color: ColoresGrafico.alerta,
            texto: '\$13,5 M',
          ),
        ],
        descripcion: 'Volcanita ST: presupuestado \$11,8 M, ejecutado \$13,5 M',
      ),
      GrupoDeBarras(
        etiqueta: 'Aislante',
        barras: const [
          BarraDeGrupo(
            valor: 50,
            color: ColoresGrafico.presupuesto,
            texto: '\$5,1 M',
          ),
          BarraDeGrupo(
            valor: 45,
            color: ColoresGrafico.ejecutado,
            texto: '\$4,9 M',
          ),
        ],
        descripcion: 'Aislante: presupuestado \$5,1 M, ejecutado \$4,9 M',
      ),
    ];

    testWidgets('muestra cada grupo con su etiqueta y el valor de cada barra', (
      tester,
    ) async {
      await _montar(
        tester,
        GraficoBarrasAgrupadas(
          grupos: grupos,
          descripcion: 'Presupuestado vs ejecutado',
        ),
      );

      expect(find.text('Volcanita ST'), findsOneWidget);
      expect(find.text('Aislante'), findsOneWidget);
      expect(find.text('\$11,8 M'), findsOneWidget);
      expect(find.text('\$13,5 M'), findsOneWidget);
      expect(find.text('\$4,9 M'), findsOneWidget);
    });

    testWidgets('el largo de cada barra es proporcional a su valor', (
      tester,
    ) async {
      await _montar(
        tester,
        GraficoBarrasAgrupadas(grupos: grupos, descripcion: 'x'),
      );

      final a = tester
          .getSize(find.byKey(const ValueKey('barra-Volcanita ST-0')))
          .width;
      final b = tester
          .getSize(find.byKey(const ValueKey('barra-Volcanita ST-1')))
          .width;
      final c = tester
          .getSize(find.byKey(const ValueKey('barra-Aislante-0')))
          .width;
      expect(b / a, closeTo(1.5, 0.01));
      expect(c / a, closeTo(0.5, 0.01));
    });

    testWidgets('la barra más larga ocupa el espacio disponible, sin pasarse', (
      tester,
    ) async {
      await _montar(
        tester,
        GraficoBarrasAgrupadas(grupos: grupos, descripcion: 'x'),
      );

      final grafico = tester.getRect(find.byType(GraficoBarrasAgrupadas));
      final barra = tester.getRect(
        find.byKey(const ValueKey('barra-Volcanita ST-1')),
      );
      expect(barra.right, lessThanOrEqualTo(grafico.right));
    });

    testWidgets('las barras llevan el color que se les dio', (tester) async {
      await _montar(
        tester,
        GraficoBarrasAgrupadas(grupos: grupos, descripcion: 'x'),
      );

      Color color(String k) {
        final caja = tester.widget<ColoredBox>(
          find.descendant(
            of: find.byKey(ValueKey(k)),
            matching: find.byType(ColoredBox),
          ),
        );
        return caja.color;
      }

      expect(color('barra-Volcanita ST-1'), ColoresGrafico.alerta);
      expect(color('barra-Aislante-1'), ColoresGrafico.ejecutado);
    });

    testWidgets('con una sola barra por grupo sirve de ranking', (
      tester,
    ) async {
      await _montar(
        tester,
        GraficoBarrasAgrupadas(
          grupos: [
            for (final (n, v) in [('Volcanita', 142.0), ('Montante', 96.0)])
              GrupoDeBarras(
                etiqueta: n,
                barras: [
                  BarraDeGrupo(
                    valor: v,
                    color: ColoresGrafico.neutro,
                    texto: '$v',
                  ),
                ],
                descripcion: '$n: $v',
              ),
          ],
          descripcion: 'Más despachados',
        ),
      );

      final a = tester
          .getSize(find.byKey(const ValueKey('barra-Volcanita-0')))
          .width;
      final b = tester
          .getSize(find.byKey(const ValueKey('barra-Montante-0')))
          .width;
      expect(a, greaterThan(b));
    });

    testWidgets('cada grupo se anuncia como un ítem, con sus cifras', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _montar(
        tester,
        GraficoBarrasAgrupadas(grupos: grupos, descripcion: 'x'),
      );

      expect(
        find.bySemanticsLabel(
          'Volcanita ST: presupuestado \$11,8 M, ejecutado \$13,5 M',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('valores en cero no rompen las proporciones', (tester) async {
      await _montar(
        tester,
        GraficoBarrasAgrupadas(
          grupos: [
            GrupoDeBarras(
              etiqueta: 'Nada',
              barras: const [
                BarraDeGrupo(
                  valor: 0,
                  color: ColoresGrafico.neutro,
                  texto: '0',
                ),
              ],
              descripcion: 'Nada: 0',
            ),
          ],
          descripcion: 'x',
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('Barras divergentes con umbral', () {
    final barras = [
      const BarraDivergente(
        etiqueta: 'Torre B',
        valor: 8.4,
        color: ColoresGrafico.alerta,
        texto: '+8,4 %',
      ),
      const BarraDivergente(
        etiqueta: 'Torre C',
        valor: 2.1,
        color: ColoresGrafico.ejecutado,
        texto: '+2,1 %',
      ),
      const BarraDivergente(
        etiqueta: 'Parque',
        valor: -1.5,
        color: ColoresGrafico.neutroMedio,
        texto: '-1,5 %',
      ),
      const BarraDivergente(
        etiqueta: 'Nueva',
        valor: null,
        color: ColoresGrafico.referencia,
        texto: 'sin presupuesto',
      ),
    ];

    testWidgets('lo positivo sale hacia la derecha del cero y lo negativo '
        'hacia la izquierda', (tester) async {
      await _montar(
        tester,
        GraficoBarrasDivergentes(
          barras: barras,
          umbral: 5,
          etiquetaUmbral: 'umbral 5 %',
          descripcion: 'Desviación por obra',
        ),
      );

      final cero = tester
          .getRect(find.byKey(const ValueKey('eje-cero')))
          .center
          .dx;
      final positiva = tester.getRect(
        find.byKey(const ValueKey('barra-Torre B')),
      );
      final negativa = tester.getRect(
        find.byKey(const ValueKey('barra-Parque')),
      );
      expect(positiva.left, closeTo(cero, 1));
      expect(positiva.right, greaterThan(cero));
      expect(negativa.right, closeTo(cero, 1));
      expect(negativa.left, lessThan(cero));
    });

    testWidgets('el largo es proporcional al valor', (tester) async {
      await _montar(
        tester,
        GraficoBarrasDivergentes(
          barras: barras,
          umbral: 5,
          etiquetaUmbral: 'umbral 5 %',
          descripcion: 'x',
        ),
      );

      final b = tester
          .getSize(find.byKey(const ValueKey('barra-Torre B')))
          .width;
      final c = tester
          .getSize(find.byKey(const ValueKey('barra-Torre C')))
          .width;
      expect(b / c, closeTo(8.4 / 2.1, 0.05));
    });

    testWidgets('dibuja la línea del umbral y la rotula', (tester) async {
      await _montar(
        tester,
        GraficoBarrasDivergentes(
          barras: barras,
          umbral: 5,
          etiquetaUmbral: 'umbral 5 %',
          descripcion: 'x',
        ),
      );

      expect(find.byKey(const ValueKey('linea-umbral')), findsOneWidget);
      expect(find.text('umbral 5 %'), findsOneWidget);
      // El umbral está entre el cero y la barra que lo supera.
      final cero = tester
          .getRect(find.byKey(const ValueKey('eje-cero')))
          .center
          .dx;
      final umbral = tester
          .getRect(find.byKey(const ValueKey('linea-umbral')))
          .center
          .dx;
      final barra = tester
          .getRect(find.byKey(const ValueKey('barra-Torre B')))
          .right;
      expect(umbral, greaterThan(cero));
      expect(umbral, lessThan(barra));
    });

    testWidgets('sin umbral no dibuja la línea', (tester) async {
      await _montar(
        tester,
        GraficoBarrasDivergentes(barras: barras, descripcion: 'x'),
      );

      expect(find.byKey(const ValueKey('linea-umbral')), findsNothing);
    });

    testWidgets('lo que no tiene valor (sin presupuesto) no dibuja barra pero '
        'lo dice', (tester) async {
      await _montar(
        tester,
        GraficoBarrasDivergentes(
          barras: barras,
          umbral: 5,
          etiquetaUmbral: 'u',
          descripcion: 'x',
        ),
      );

      expect(find.byKey(const ValueKey('barra-Nueva')), findsNothing);
      expect(find.text('sin presupuesto'), findsOneWidget);
      expect(find.text('Nueva'), findsOneWidget);
    });

    testWidgets('muestra la etiqueta y el valor de cada obra', (tester) async {
      await _montar(
        tester,
        GraficoBarrasDivergentes(
          barras: barras,
          umbral: 5,
          etiquetaUmbral: 'u',
          descripcion: 'x',
        ),
      );

      for (final t in [
        'Torre B',
        '+8,4 %',
        'Torre C',
        '+2,1 %',
        'Parque',
        '-1,5 %',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
    });

    testWidgets('todo negativo o todo cero no rompe la escala', (tester) async {
      await _montar(
        tester,
        GraficoBarrasDivergentes(
          barras: const [
            BarraDivergente(
              etiqueta: 'A',
              valor: -3,
              color: ColoresGrafico.neutroMedio,
              texto: '-3 %',
            ),
            BarraDivergente(
              etiqueta: 'B',
              valor: 0,
              color: ColoresGrafico.neutroMedio,
              texto: '0 %',
            ),
          ],
          umbral: 5,
          etiquetaUmbral: 'u',
          descripcion: 'x',
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('cada obra se anuncia con su cifra', (tester) async {
      final handle = tester.ensureSemantics();
      await _montar(
        tester,
        GraficoBarrasDivergentes(
          barras: [
            const BarraDivergente(
              etiqueta: 'Torre B',
              valor: 8.4,
              color: ColoresGrafico.alerta,
              texto: '+8,4 %',
              descripcion: 'Torre B: +8,4 %, supera el umbral',
            ),
          ],
          umbral: 5,
          etiquetaUmbral: 'u',
          descripcion: 'x',
        ),
      );

      expect(
        find.bySemanticsLabel('Torre B: +8,4 %, supera el umbral'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('Dona con leyenda', () {
    final segmentos = [
      const SegmentoDona(
        etiqueta: 'Volcanita ST',
        valor: 26,
        color: ColoresGrafico.ejecutado,
        texto: '26 %',
      ),
      const SegmentoDona(
        etiqueta: 'Metalcom',
        valor: 20,
        color: ColoresGrafico.neutro,
        texto: '20 %',
      ),
      const SegmentoDona(
        etiqueta: 'Otros materiales',
        valor: 54,
        color: ColoresGrafico.presupuesto,
        texto: '54 %',
      ),
    ];

    testWidgets('dibuja un sector por segmento, del tamaño de su valor', (
      tester,
    ) async {
      await _montar(
        tester,
        GraficoDona(
          segmentos: segmentos,
          centroValor: '52,3',
          centroEtiqueta: 'M\$ ejecutado',
          descripcion: 'Ejecutado por material',
        ),
      );

      final secciones = tester
          .widget<PieChart>(find.byType(PieChart))
          .data
          .sections;
      expect(secciones.map((s) => s.value), [26, 20, 54]);
      expect(secciones.map((s) => s.color), [
        ColoresGrafico.ejecutado,
        ColoresGrafico.neutro,
        ColoresGrafico.presupuesto,
      ]);
    });

    testWidgets('el centro lleva la cifra y su unidad', (tester) async {
      await _montar(
        tester,
        GraficoDona(
          segmentos: segmentos,
          centroValor: '52,3',
          centroEtiqueta: 'M\$ ejecutado',
          descripcion: 'x',
        ),
      );

      expect(find.text('52,3'), findsOneWidget);
      expect(find.text('M\$ ejecutado'), findsOneWidget);
    });

    testWidgets('la leyenda dice cada segmento y su valor, no solo el color', (
      tester,
    ) async {
      await _montar(
        tester,
        GraficoDona(
          segmentos: segmentos,
          centroValor: '52,3',
          centroEtiqueta: 'M\$ ejecutado',
          descripcion: 'x',
        ),
      );

      for (final t in [
        'Volcanita ST',
        '26 %',
        'Metalcom',
        '20 %',
        'Otros materiales',
        '54 %',
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
    });

    testWidgets('un segmento en cero no se dibuja pero sigue en la leyenda', (
      tester,
    ) async {
      await _montar(
        tester,
        GraficoDona(
          segmentos: const [
            SegmentoDona(
              etiqueta: 'A',
              valor: 10,
              color: ColoresGrafico.ejecutado,
              texto: '10',
            ),
            SegmentoDona(
              etiqueta: 'B',
              valor: 0,
              color: ColoresGrafico.neutro,
              texto: '0',
            ),
          ],
          centroValor: '10',
          centroEtiqueta: 'total',
          descripcion: 'x',
        ),
      );

      final secciones = tester
          .widget<PieChart>(find.byType(PieChart))
          .data
          .sections;
      expect(secciones.where((s) => s.value > 0), hasLength(1));
      expect(find.text('B'), findsOneWidget);
    });

    testWidgets('se anuncia como un solo gráfico con la descripción', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _montar(
        tester,
        GraficoDona(
          segmentos: segmentos,
          centroValor: '52,3',
          centroEtiqueta: 'x',
          descripcion: 'Volcanita 26 %, Metalcom 20 %, Otros 54 %',
        ),
      );

      expect(
        find.bySemanticsLabel(
          'Gráfico de dona. Volcanita 26 %, Metalcom 20 %, Otros 54 %',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('con el texto muy grande la leyenda no se desborda', (
      tester,
    ) async {
      await _montar(
        tester,
        GraficoDona(
          segmentos: segmentos,
          centroValor: '52,3',
          centroEtiqueta: 'M\$ ejecutado',
          descripcion: 'x',
        ),
        escala: 2,
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('Tarjeta de métrica', () {
    testWidgets('lleva título, cifra, detalle, gráfico y leyenda', (
      tester,
    ) async {
      await _montar(
        tester,
        const TarjetaMetrica(
          titulo: 'Gasto acumulado por semana',
          cifra: '\$52,3 M',
          detalle: 'ejecutado · presupuesto \$48,2 M',
          leyenda: [
            ItemLeyenda(
              etiqueta: 'Ejecutado acumulado',
              color: ColoresGrafico.ejecutado,
            ),
            ItemLeyenda(
              etiqueta: 'Presupuesto',
              color: ColoresGrafico.referencia,
              estilo: EstiloLeyenda.lineaPunteada,
            ),
          ],
          child: SizedBox(height: 40, child: Text('el gráfico')),
        ),
      );

      expect(find.text('Gasto acumulado por semana'), findsOneWidget);
      expect(find.text('\$52,3 M'), findsOneWidget);
      expect(find.text('ejecutado · presupuesto \$48,2 M'), findsOneWidget);
      expect(find.text('el gráfico'), findsOneWidget);
      expect(find.text('Ejecutado acumulado'), findsOneWidget);
      expect(find.text('Presupuesto'), findsOneWidget);
    });

    testWidgets('el título es un encabezado para el lector de pantalla', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _montar(
        tester,
        const TarjetaMetrica(
          titulo: 'Usuarios por rol',
          cifra: '11',
          detalle: 'son trabajadores',
          child: SizedBox(),
        ),
      );

      expect(
        tester.getSemantics(find.text('Usuarios por rol')),
        matchesSemantics(label: 'Usuarios por rol', isHeader: true),
      );
      handle.dispose();
    });

    testWidgets('la cifra puede ir en rojo cuando algo se pasó', (
      tester,
    ) async {
      await _montar(
        tester,
        const TarjetaMetrica(
          titulo: 't',
          cifra: '+14,4 %',
          detalle: 'd',
          colorCifra: ColoresGrafico.alertaOscura,
          child: SizedBox(),
        ),
      );

      final texto = tester.widget<Text>(find.text('+14,4 %'));
      expect(texto.style!.color, ColoresGrafico.alertaOscura);
    });

    testWidgets('sin cifra ni detalle, solo el título y el gráfico', (
      tester,
    ) async {
      await _montar(
        tester,
        const TarjetaMetrica(titulo: 'Solo título', child: Text('contenido')),
      );

      expect(find.text('Solo título'), findsOneWidget);
      expect(find.text('contenido'), findsOneWidget);
    });
  });

  group('Estado vacío del gráfico', () {
    testWidgets('dice con claridad que no hay datos', (tester) async {
      await _montar(
        tester,
        const GraficoVacio(mensaje: 'Todavía no hay gasto en este periodo.'),
      );

      expect(
        find.text('Todavía no hay gasto en este periodo.'),
        findsOneWidget,
      );
    });

    testWidgets('reserva el alto del gráfico para que la tarjeta no salte', (
      tester,
    ) async {
      await _montar(tester, const GraficoVacio(mensaje: 'x', alto: 128));

      expect(
        tester.getSize(find.byType(GraficoVacio)).height,
        greaterThanOrEqualTo(128),
      );
    });
  });

  group('Detalles de legibilidad', () {
    testWidgets('con un máximo pequeño el eje vertical usa solo enteros', (
      tester,
    ) async {
      // Alertas por semana con máximo 1: el eje decía «1, 1, 0» porque el
      // paso de 0,5 se escribía sin decimales.
      await _montar(
        tester,
        GraficoLinea(
          etiquetasX: const ['S1', 'S2', 'S3'],
          series: [
            SerieLinea(
              nombre: 'Generadas',
              valores: const [0, 0, 1],
              color: ColoresGrafico.ejecutado,
            ),
          ],
          descripcion: 'Alertas',
        ),
      );

      final datos = tester.widget<LineChart>(find.byType(LineChart)).data;
      expect(datos.gridData.horizontalInterval, greaterThanOrEqualTo(1));
      expect(datos.maxY, 1);
      // Las marcas del eje: ninguna repetida.
      final rotulos = [
        for (final t in tester.widgetList<Text>(find.byType(Text)))
          if (t.data == '0' || t.data == '1') t.data,
      ];
      expect(rotulos.toSet().length, rotulos.length, reason: '$rotulos');
    });

    testWidgets('un eje con formato propio conserva sus fracciones', (
      tester,
    ) async {
      // Los millones del gasto sí usan 0,5: el cambio es solo para enteros.
      await _montar(
        tester,
        GraficoLinea(
          etiquetasX: const ['S1', 'S2'],
          series: [
            SerieLinea(
              nombre: 'Gasto',
              valores: const [0, 1.5],
              color: ColoresGrafico.ejecutado,
            ),
          ],
          descripcion: 'Gasto',
          formatoY: (v) => v.toStringAsFixed(1),
        ),
      );

      final datos = tester.widget<LineChart>(find.byType(LineChart)).data;
      expect(datos.gridData.horizontalInterval, lessThan(1));
    });

    testWidgets('el rótulo «Supera el presupuesto» queda fuera del trazo', (
      tester,
    ) async {
      await _montar(
        tester,
        GraficoLinea(
          etiquetasX: const ['S1', 'S2', 'S3'],
          series: [
            SerieLinea(
              nombre: 'Ejecutado',
              valores: const [0, 1, 1.5],
              color: ColoresGrafico.ejecutado,
              conArea: true,
            ),
            SerieLinea(
              nombre: 'Presupuesto',
              valores: const [1.4, 1.4, 1.4],
              color: ColoresGrafico.referencia,
              punteada: true,
            ),
          ],
          descripcion: 'Gasto',
          marcaFinal: 'Supera el presupuesto',
        ),
      );

      final rotulo = tester.getRect(find.text('Supera el presupuesto'));
      final trazo = tester.getRect(find.byType(LineChart));
      // La línea de presupuesto corre por la parte alta del trazo: el rótulo
      // va por encima, no encima de ella.
      expect(rotulo.bottom, lessThanOrEqualTo(trazo.top));
    });

    testWidgets('el centro de la dona cabe en su círculo interior', (
      tester,
    ) async {
      await _montar(
        tester,
        const GraficoDona(
          segmentos: [
            SegmentoDona(
              etiqueta: 'Volcanita',
              valor: 52,
              color: ColoresGrafico.ejecutado,
              texto: '52 %',
            ),
          ],
          centroValor: '\$1,5 M',
          centroEtiqueta: 'ejecutado',
          descripcion: 'x',
        ),
        escala: 1,
      );

      final anillo = tester.getRect(find.byType(PieChart));
      final centro = anillo.center;
      const radioInterior = 112 / 2 - 22; // lado / 2 − grosor
      for (final texto in ['\$1,5 M', 'ejecutado']) {
        final r = tester.getRect(find.text(texto));
        for (final esquina in [
          r.topLeft,
          r.topRight,
          r.bottomLeft,
          r.bottomRight,
        ]) {
          expect(
            (esquina - centro).distance,
            lessThanOrEqualTo(radioInterior),
            reason: '«$texto» roza el borde interior en $esquina',
          );
        }
      }
    });
  });
}
