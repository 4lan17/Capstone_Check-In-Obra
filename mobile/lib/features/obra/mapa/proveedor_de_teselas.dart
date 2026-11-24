import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Los tiles de OpenStreetMap. Su política de uso pide no precargar mapas en
/// masa y mostrar siempre la atribución: acá solo se piden los tiles que se ven.
const urlDeTeselasOsm = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Con qué paquete se identifica la app ante el servidor de tiles (es el
/// `applicationId` de Android). Sin esto, OSM no sabe a quién avisarle si la
/// app se pasa de las solicitudes permitidas.
const paqueteDeLaApp = 'cl.duocuc.checkinobra_mobile';

/// Quien trae los tiles. Es un provider para poder cambiarlo en las pruebas:
/// con uno falso se prueba "hay red" y "no hay red" sin tocar internet.
final proveedorDeTeselasProvider = Provider<TileProvider>((ref) {
  final proveedor = NetworkTileProvider();
  ref.onDispose(proveedor.dispose);
  return proveedor;
});
