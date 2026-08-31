import 'package:checkinobra_mobile/shared_widgets/estados.dart';
import 'package:checkinobra_mobile/shared_widgets/panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dos tarjetas lado a lado con descripciones de largo distinto — la misma
/// forma que tienen "Movimiento" y "Préstamo" en el inicio de bodega.
Widget _dosTarjetas() {
  return MaterialApp(
    home: Scaffold(
      // Un ListView deja la altura sin acotar, que es la condición real de la
      // pantalla. Sin el IntrinsicHeight, `stretch` intenta darle a cada hijo
      // una restricción tirante de altura infinita y la pantalla no dibuja.
      body: ListView(
        children: [
          SizedBox(
            width: 300,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: PanelTocable(
                      semanticLabel: 'larga',
                      onTap: () {},
                      child: const Text('Recepción, despacho o consumo'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PanelTocable(
                      semanticLabel: 'corta',
                      onTap: () {},
                      child: const Text('Entregar'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

double _altoDe(WidgetTester tester, String etiqueta) =>
    tester.getSize(find.bySemanticsLabel(etiqueta)).height;

void main() {
  testWidgets('los dos accesos rápidos miden lo mismo', (tester) async {
    // El de la izquierda lleva una descripción de dos líneas y el de la
    // derecha una de una sola. Sin igualarlos, la fila queda despareja.
    await tester.pumpWidget(_dosTarjetas());

    expect(_altoDe(tester, 'larga'), _altoDe(tester, 'corta'));
  });

  testWidgets('el contador centra la cifra y su rótulo en la columna', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Expanded(
                child: Contador(valor: '3', rotulo: 'Movimientos\ndel turno'),
              ),
              Expanded(
                child: Contador(valor: '6', rotulo: 'Alertas\nsin resolver'),
              ),
            ],
          ),
        ),
      ),
    );

    // La cifra y su rótulo comparten centro horizontal: alineados a la
    // izquierda, el "3" quedaba descolgado de un rótulo mucho más ancho.
    final cifra = tester.getCenter(find.text('3'));
    final rotulo = tester.getCenter(find.text('Movimientos\ndel turno'));
    expect(cifra.dx, closeTo(rotulo.dx, 0.5));
  });
}
