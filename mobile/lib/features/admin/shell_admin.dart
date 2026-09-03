import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/api/dominio_api.dart';
import '../../data/modelos/usuario.dart';
import '../../shared_widgets/estados.dart';
import '../../shared_widgets/panel.dart';
import '../auth/sesion_controller.dart';
import '../bodega/bodega_providers.dart';
import '../bodega/shell_bodega.dart';
import '../obra/obra_activa.dart';
import 'pantalla_importacion.dart';
import 'pantalla_materiales.dart';
import 'pantalla_obras.dart';
import 'pantalla_usuarios.dart';

final empresaProvider = FutureProvider<Empresa>(
  (ref) => ref.watch(empresaApiProvider).mia(),
);

/// La app del administrador: configura la empresa y entra a bodega cuando hace
/// falta.
///
/// El admin no tiene obra activa como el bodeguero — trabaja sobre la empresa
/// entera— así que su shell no exige elegir una. La elige recién al abrir la
/// vista de bodega.
class ShellAdmin extends ConsumerStatefulWidget {
  const ShellAdmin({super.key});

  @override
  ConsumerState<ShellAdmin> createState() => _ShellAdminState();
}

class _ShellAdminState extends ConsumerState<ShellAdmin> {
  int _tab = 0;

  static const _titulos = ['Obras', 'Materiales', 'Usuarios', 'Empresa'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ADMINISTRACIÓN',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                color: AppColors.textOnDark,
              ),
            ),
            Text(
              _titulos[_tab],
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
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: _tab,
          children: const [
            PantallaObras(),
            PantallaMateriales(),
            PantallaUsuarios(),
            _PantallaEmpresa(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: AppColors.card,
        indicatorColor: AppColors.warningTint,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.domain_outlined),
            selectedIcon: Icon(Icons.domain),
            label: 'Obras',
          ),
          NavigationDestination(
            icon: Icon(Icons.category_outlined),
            selectedIcon: Icon(Icons.category),
            label: 'Materiales',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Usuarios',
          ),
          NavigationDestination(
            icon: Icon(Icons.business_outlined),
            selectedIcon: Icon(Icons.business),
            label: 'Empresa',
          ),
        ],
      ),
    );
  }
}

class _PantallaEmpresa extends ConsumerWidget {
  const _PantallaEmpresa();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final empresa = ref.watch(empresaProvider);
    final sesion = ref.watch(sesionProvider).valueOrNull;
    final obras = ref.watch(todasLasObrasProvider).valueOrNull;
    final materiales = ref.watch(catalogoProvider).valueOrNull;
    final usuarios = ref.watch(usuariosProvider).valueOrNull;

    return RefreshIndicator(
      onRefresh: () async => ref.refresh(empresaProvider.future),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Contenido<Empresa>(
            valor: empresa,
            alReintentar: () => ref.invalidate(empresaProvider),
            constructor: (e) => Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.nombre,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    e.rut,
                    style: const TextStyle(
                      fontFamily: AppTheme.monoFamily,
                      fontSize: 12.5,
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Panel(
            child: Row(
              children: [
                Expanded(
                  child: Contador(
                    valor: '${obras?.where((o) => o.activa).length ?? 0}',
                    rotulo: 'Obras\nactivas',
                  ),
                ),
                Expanded(
                  child: Contador(
                    valor: '${usuarios?.length ?? 0}',
                    rotulo: 'Usuarios',
                  ),
                ),
                Expanded(
                  child: Contador(
                    valor: '${materiales?.length ?? 0}',
                    rotulo: 'Materiales',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Etiqueta('Operación'),
          const SizedBox(height: 8),
          PanelTocable(
            semanticLabel:
                'Abrir la vista de bodega. El administrador puede registrar '
                'movimientos y préstamos igual que un bodeguero',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ShellBodega(comoAdmin: true),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  size: 22,
                  color: AppColors.accentFill,
                ),
                const SizedBox(width: 13),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vista de bodega',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Kardex, herramientas y alertas de una obra. Tu rol '
                        'incluye todo lo de bodega.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 22,
                  color: AppColors.accentFill,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          PanelTocable(
            semanticLabel:
                'Importación masiva. Cargar materiales y herramientas desde '
                'una planilla Excel',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PantallaImportacion()),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.table_view_outlined,
                  size: 22,
                  color: AppColors.accentFill,
                ),
                const SizedBox(width: 13),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Importación masiva',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Cargar materiales y herramientas nuevos desde una '
                        'planilla Excel, en vez de uno por uno.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 22,
                  color: AppColors.accentFill,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Etiqueta('Sesión'),
          const SizedBox(height: 8),
          Panel(
            child: Row(
              children: [
                Iniciales(sesion?.nombre ?? '?', tamano: 44),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sesion?.nombre ?? '',
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        nombreDeRol(sesion?.rol ?? ''),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
