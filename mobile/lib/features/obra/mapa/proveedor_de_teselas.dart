import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Los tiles de OpenStreetMap. Su política de uso pide no precargar mapas en
/// masa y mostrar siempre la atribución: acá solo se piden los tiles que se ven.
const urlDeTeselasOsm = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Con qué paquete se identifica la app ante el servidor de tiles (es el
/// `applicationId` de Android). Sin esto, OSM no sabe a quién avisarle si la
/// app se pasa de las solicitudes permitidas.
const paqueteDeLaApp = 'cl.duocuc.checkinobra_mobile';

/// Cuánto se espera antes de volver a pedir los tiles que no llegaron: 2 s y
/// después 4 s. Son solo dos reintentos y con espera creciente: la política de
/// uso de OSM no admite insistir en ráfagas sobre un servidor que no responde.
const esperasDeReintentoDeTeselas = [
  Duration(seconds: 2),
  Duration(seconds: 4),
];

/// El cliente HTTP con que se piden **todos** los tiles de la app.
///
/// Es uno solo y es **nuestro**, no el que `NetworkTileProvider` crea por su
/// cuenta: `TileLayer.dispose()` llama a `TileProvider.dispose()`, y un
/// proveedor con cliente propio lo cierra. Con un proveedor compartido eso
/// significaba que, la primera vez que un mapa salía de la pantalla (o la
/// lista lo descartaba al desplazarse), el cliente quedaba cerrado y **todos**
/// los tiles siguientes fallaban: huecos en las cards y el mapa grande en
/// blanco. Acá solo se cierra al cerrar la app. Compartirlo además reutiliza
/// la conexión, que es lo que OSM pide.
final clienteHttpDeTeselasProvider = Provider<http.Client>((ref) {
  final cliente = http.Client();
  ref.onDispose(cliente.close);
  return cliente;
});

/// Quien trae los tiles. Es un provider para poder cambiarlo en las pruebas:
/// con uno falso se prueba "hay red" y "no hay red" sin tocar internet.
final proveedorDeTeselasProvider = Provider<TileProvider>(
  (ref) =>
      NetworkTileProvider(httpClient: ref.watch(clienteHttpDeTeselasProvider)),
);

/// Las esperas de los reintentos. Es un provider solo para poder acortarlas
/// en las pruebas que no miran el tiempo.
final esperasDeReintentoDeTeselasProvider = Provider<List<Duration>>(
  (ref) => esperasDeReintentoDeTeselas,
);
