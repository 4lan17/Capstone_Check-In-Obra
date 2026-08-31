import 'dart:math' as math;

import 'package:checkinobra_mobile/core/theme/app_colors.dart';
import 'package:checkinobra_mobile/shared_widgets/panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fija lo que la revisión de UI dejó arreglado, para que no se pierda al
/// escribir las pantallas de cada rol encima de esta base.
void main() {
  group('PanelTocable', () {
    testWidgets('se anuncia como botón con su etiqueta', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PanelTocable(
              onTap: () {},
              semanticLabel: 'Entrar como Jorge Reyes',
              child: const Text('Jorge Reyes'),
            ),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.bySemanticsLabel('Entrar como Jorge Reyes')),
        matchesSemantics(
          label: 'Entrar como Jorge Reyes',
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );

      handle.dispose();
    });

    testWidgets(
      'pone el Material por fuera del InkWell, para que el toque se vea',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PanelTocable(
                onTap: () {},
                semanticLabel: 'x',
                child: const Text('x'),
              ),
            ),
          ),
        );

        // Si el orden se invierte, el fondo opaco vuelve a tapar el splash y la
        // app deja de acusar recibo del toque.
        final material = find.descendant(
          of: find.byType(PanelTocable),
          matching: find.byType(Material),
        );
        expect(material, findsOneWidget);
        expect(
          find.descendant(of: material.first, matching: find.byType(InkWell)),
          findsOneWidget,
        );
      },
    );

    testWidgets('no propaga el toque cuando onTap es nulo', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PanelTocable(
              onTap: null,
              semanticLabel: 'deshabilitado',
              child: Text('x'),
            ),
          ),
        ),
      );

      final inkWell = tester.widget<InkWell>(find.byType(InkWell));
      expect(inkWell.onTap, isNull);
    });
  });

  group('ChipEstado', () {
    testWidgets('no desborda con el texto del sistema al máximo', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(3)),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 200,
                  child: Row(children: [ChipEstado.critico('SIN CONEXIÓN')]),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('Paleta', () {
    /// Los umbrales de WCAG que el design system adoptó: 4.5:1 para texto,
    /// 3:1 para el contorno que identifica un control.
    double contraste(Color a, Color b) {
      double canal(double c) => c <= 0.03928
          ? c / 12.92
          : math.pow((c + 0.055) / 1.055, 2.4) as double;
      double luz(Color c) =>
          0.2126 * canal(c.r) + 0.7152 * canal(c.g) + 0.0722 * canal(c.b);
      final (la, lb) = (luz(a), luz(b));
      final (alto, bajo) = la > lb ? (la, lb) : (lb, la);
      return (alto + 0.05) / (bajo + 0.05);
    }

    test('el texto sobre superficie oscura pasa 4.5:1', () {
      expect(
        contraste(AppColors.textOnDark, AppColors.primary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contraste(AppColors.textOnDark, AppColors.surfaceDark),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('el borde de un control pasa 3:1 sobre sus dos fondos', () {
      expect(
        contraste(AppColors.borderControl, AppColors.background),
        greaterThanOrEqualTo(3.0),
      );
      expect(
        contraste(AppColors.borderControl, AppColors.card),
        greaterThanOrEqualTo(3.0),
      );
    });

    test('textFaint no alcanza para texto — por eso existe textOnDark', () {
      expect(contraste(AppColors.textFaint, AppColors.primary), lessThan(4.5));
    });
  });
}
