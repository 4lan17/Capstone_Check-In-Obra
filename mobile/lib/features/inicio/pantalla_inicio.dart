import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/auth_api.dart';
import '../../shared_widgets/panel.dart';
import '../auth/sesion_controller.dart';

/// Pantalla posterior al acceso. Por ahora confirma quién entró y qué le
/// habilita su rol; el contenido real de cada rol se construye encima.
///
/// La navegación inferior cambia según el rol (el jefe de terreno no escanea,
/// el admin no tiene bodega), así que cada rol tendrá su propio shell.
class PantallaInicio extends ConsumerWidget {
  const PantallaInicio({super.key, required this.sesion});

  final SesionUsuario sesion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permisos = _permisosDe(sesion.rol);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              nombreDeRol(sesion.rol).toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: AppColors.textFaint,
              ),
            ),
            Text(
              sesion.nombre,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(sesionProvider.notifier).salir(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Panel(
              child: Row(
                children: [
                  Iniciales(sesion.nombre, tamano: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sesion.nombre,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Empresa #${sesion.empresaId} · usuario #${sesion.usuarioId}',
                          style: const TextStyle(
                            fontFamily: AppTheme.monoFamily,
                            fontSize: 11.5,
                            color: AppColors.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ChipEstado.neutro(sesion.rol),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Etiqueta('Lo que habilita tu rol'),
            const SizedBox(height: 8),
            Panel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < permisos.length; i++)
                    Container(
                      decoration: BoxDecoration(
                        border: i < permisos.length - 1
                            ? const Border(
                                bottom: BorderSide(color: AppColors.border),
                              )
                            : null,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.check,
                            size: 18,
                            color: AppColors.successDark,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              permisos[i],
                              style: const TextStyle(
                                fontSize: 13.5,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Panel(
              color: AppColors.warningTint,
              borderColor: AppColors.warning,
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.construction_outlined,
                    size: 20,
                    color: AppColors.warningDark,
                  ),
                  SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      'Autenticación lista. Las pantallas de cada rol se '
                      'construyen a continuación sobre esta base.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Refleja la matriz de permisos del README y los `@PreAuthorize` del backend.
  List<String> _permisosDe(String rol) => switch (rol) {
    'TRABAJADOR' => const [
      'Solicitar herramienta o material',
      'Mostrar credencial QR',
      'Ver sus préstamos y devoluciones',
    ],
    'BODEGUERO' => const [
      'Aprobar o rechazar solicitudes',
      'Recepción, despacho y consumo',
      'Autorizar préstamo y registrar devolución',
      'Cerrar turno de bodega',
      'Resolver alertas',
    ],
    'JEFE_TERRENO' => const [
      'Cubicar partidas',
      'Congelar el presupuesto',
      'Ver la desviación de la obra',
      'Resolver alertas',
    ],
    'ADMIN' => const [
      'Crear usuarios y asignar rol',
      'Definir catálogo, precios y mermas',
      'Crear y cerrar obras',
      'Todo lo de bodega y terreno',
    ],
    _ => const ['Rol no reconocido'],
  };
}
