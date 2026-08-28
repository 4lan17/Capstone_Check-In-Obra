import 'package:checkinobra_mobile/core/storage/sesion_storage.dart';
import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/features/inicio/pantalla_inicio.dart';
import 'package:checkinobra_mobile/shared_widgets/panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Iniciales', () {
    test('toma la primera letra de nombre y apellido', () {
      expect(Iniciales.de('Marcelo Sepúlveda'), 'MS');
    });

    test('con un solo nombre usa una letra', () {
      expect(Iniciales.de('Jorge'), 'J');
    });

    test('ignora los espacios de más', () {
      expect(Iniciales.de('  Camila   Bravo  '), 'CB');
    });

    test('no revienta con texto vacío', () {
      expect(Iniciales.de('   '), '?');
    });
  });

  group('SesionUsuario', () {
    test('sobrevive al viaje de ida y vuelta a JSON', () {
      const original = SesionUsuario(
        token: 'abc.def.ghi',
        usuarioId: 7,
        nombre: 'Jorge Reyes',
        rol: 'BODEGUERO',
        empresaId: 1,
      );
      final copia = SesionUsuario.desdeJson(original.aJson());

      expect(copia.token, original.token);
      expect(copia.usuarioId, original.usuarioId);
      expect(copia.nombre, original.nombre);
      expect(copia.rol, original.rol);
      expect(copia.empresaId, original.empresaId);
    });
  });

  group('UsuarioRecordado', () {
    test('guarda los datos mínimos para el acceso por PIN', () {
      const u = UsuarioRecordado(
        usuarioId: 3,
        nombre: 'Marcelo Sepúlveda',
        rol: 'TRABAJADOR',
      );
      expect(u.usuarioId, 3);
      expect(Iniciales.de(u.nombre), 'MS');
    });
  });

  testWidgets('el inicio muestra el rol y sus permisos', (tester) async {
    const sesion = SesionUsuario(
      token: 't',
      usuarioId: 1,
      nombre: 'Jorge Reyes',
      rol: 'BODEGUERO',
      empresaId: 1,
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: PantallaInicio(sesion: sesion)),
      ),
    );
    await tester.pump();

    expect(find.text('Jorge Reyes'), findsWidgets);
    expect(find.text('BODEGUERO'), findsWidgets);
    // Un permiso propio del bodeguero, y ninguno ajeno a su rol.
    expect(find.text('Aprobar o rechazar solicitudes'), findsOneWidget);
    expect(find.text('Congelar el presupuesto'), findsNothing);
  });
}
