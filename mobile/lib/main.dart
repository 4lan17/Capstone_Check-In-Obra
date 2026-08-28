import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/network/app_config.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/pantalla_acceso.dart';
import 'features/auth/sesion_controller.dart';
import 'features/inicio/pantalla_inicio.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.cargar();
  runApp(const ProviderScope(child: Check-In-ObraApp()));
}

class Check-In-ObraApp extends StatelessWidget {
  const Check-In-ObraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Check-In-Obra',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const _Raiz(),
    );
  }
}

/// Decide qué mostrar según haya sesión guardada o no.
///
/// Al abrir la app se lee el token del almacenamiento cifrado: si sigue ahí,
/// se entra directo. Pedir credenciales cada vez que se abre la app sería
/// inaceptable en obra.
class _Raiz extends ConsumerWidget {
  const _Raiz();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(sesionProvider);

    return switch (sesion) {
      // Primera carga: aún no sabemos si hay sesión guardada.
      AsyncLoading() when !sesion.hasValue => const _Cargando(),
      AsyncValue(value: final s?) => PantallaInicio(sesion: s),
      _ => const PantallaAcceso(),
    };
  }
}

class _Cargando extends StatelessWidget {
  const _Cargando();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}
