import 'package:checkinobra_mobile/core/navegacion.dart';
import 'package:checkinobra_mobile/core/network/api_client.dart';
import 'package:checkinobra_mobile/core/storage/sesion_storage.dart';
import 'package:checkinobra_mobile/data/api/auth_api.dart';
import 'package:checkinobra_mobile/features/auth/pantalla_acceso.dart';
import 'package:checkinobra_mobile/features/auth/pantalla_acceso_pin.dart';
import 'package:checkinobra_mobile/features/auth/sesion_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _AuthFalsa implements AuthApi {
  @override
  Future<SesionUsuario> loginPorPin({
    required int usuarioId,
    required String pin,
  }) async => SesionUsuario(
    token: 't',
    usuarioId: usuarioId,
    nombre: 'Jorge Reyes',
    rol: 'BODEGUERO',
    empresaId: 1,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SinSesion extends SesionController {
  @override
  Future<SesionUsuario?> build() async => null;
}

Future<void> _abrir(WidgetTester tester, {UsuarioRecordado? recordado}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sesionProvider.overrideWith(_SinSesion.new),
        usuarioRecordadoProvider.overrideWith((ref) async => recordado),
      ],
      child: const MaterialApp(home: PantallaAcceso()),
    ),
  );
  await tester.pumpAndSettle();
}

const _jorge = UsuarioRecordado(
  usuarioId: 7,
  nombre: 'Jorge Reyes',
  rol: 'BODEGUERO',
);

void main() {
  testWidgets('quien el teléfono recuerda entra con un toque, sin formulario', (
    tester,
  ) async {
    // En obra es el caso de todos los días: el mismo bodeguero en el mismo
    // teléfono. El formulario de correo no se muestra hasta que se pide.
    await _abrir(tester, recordado: _jorge);

    expect(find.text('Jorge'), findsOneWidget);
    expect(find.text('Entrar con mi PIN'), findsOneWidget);
    expect(find.text('Correo de empresa'), findsNothing);
  });

  testWidgets('"Usar otro correo" abre el formulario y se puede volver', (
    tester,
  ) async {
    await _abrir(tester, recordado: _jorge);

    await tester.tap(find.text('Usar otro correo'));
    await tester.pumpAndSettle();
    expect(find.text('Correo de empresa'), findsOneWidget);
    expect(find.text('Entrar con mi PIN'), findsNothing);

    // Queda al pie del formulario, fuera de la vista de prueba.
    final volver = find.text('Volver a entrar como Jorge');
    await tester.ensureVisible(volver);
    await tester.pumpAndSettle();
    await tester.tap(volver);
    await tester.pumpAndSettle();
    expect(find.text('Entrar con mi PIN'), findsOneWidget);
  });

  testWidgets('sin nadie recordado va directo al correo', (tester) async {
    await _abrir(tester);

    expect(find.text('Inicia sesión'), findsOneWidget);
    expect(find.text('Correo de empresa'), findsOneWidget);
    expect(find.textContaining('Volver a entrar como'), findsNothing);
  });

  testWidgets('un PIN correcto cierra la pantalla del teclado', (tester) async {
    // El bug: tras el PIN correcto, la pantalla del teclado quedaba apilada
    // encima de la app con los cuatro puntos llenos.
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sesionProvider.overrideWith(_SinSesion.new),
          usuarioRecordadoProvider.overrideWith((ref) async => _jorge),
          authApiProvider.overrideWithValue(_AuthFalsa()),
        ],
        child: MaterialApp(
          navigatorKey: navegadorRaiz,
          home: const PantallaAcceso(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Entrar con mi PIN'));
    await tester.pumpAndSettle();
    expect(find.byType(PantallaAccesoPin), findsOneWidget);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.bySemanticsLabel('2'));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(find.byType(PantallaAccesoPin), findsNothing);
  });
}
