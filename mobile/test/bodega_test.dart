import 'package:checkinobra_mobile/core/formato.dart';
import 'package:checkinobra_mobile/data/modelos/kardex.dart';
import 'package:checkinobra_mobile/data/modelos/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

MaterialObra _material({double minimo = 40}) => MaterialObra(
  id: 1,
  sku: 'VOL-ST-10',
  nombre: 'Volcanita ST 10 mm',
  categoria: 'VOLCANITA',
  precioUnitario: 5980,
  stockMinimo: minimo,
);

MovimientoKardex _mov(
  String tipo,
  double cantidad, {
  String? receptorNombre,
  String? receptorRut,
}) => MovimientoKardex(
  id: 1,
  tipo: tipo,
  cantidad: cantidad,
  fecha: DateTime(2026, 8, 30, 9),
  materialId: 1,
  materialSku: 'VOL-ST-10',
  materialNombre: 'Volcanita ST 10 mm',
  usuarioNombre: 'Jorge Reyes',
  trabajadorNombre: receptorNombre,
  trabajadorRut: receptorRut,
);

void main() {
  setUpAll(() => initializeDateFormatting('es_CL'));

  group('Signo del movimiento', () {
    test('la recepción suma y el despacho y el consumo restan', () {
      expect(_mov('RECEPCION', 72).cantidadConSigno, 72);
      expect(_mov('DESPACHO', 36).cantidadConSigno, -36);
      expect(_mov('CONSUMO', 4).cantidadConSigno, -4);
    });

    test('la cantidad guardada siempre es positiva', () {
      // El backend rechaza cantidades <= 0: el signo lo pone el tipo, nunca
      // el valor. Si esto cambiara, un SUM(cantidad) dejaría de significar
      // nada.
      for (final tipo in ['RECEPCION', 'DESPACHO', 'CONSUMO']) {
        expect(_mov(tipo, 10).cantidad, isPositive);
      }
    });
  });

  group('Quién recibió el material', () {
    test('un despacho identifica al receptor por nombre y RUT', () {
      // Es el dato que se busca cuando aparece un descuadre: el nombre solo no
      // basta si en la obra hay dos Marcelos.
      final despacho = _mov(
        'DESPACHO',
        36,
        receptorNombre: 'Marcelo Sepúlveda',
        receptorRut: '17.930.556-4',
      );
      expect(despacho.receptor, 'Marcelo Sepúlveda · 17.930.556-4');
    });

    test('una recepción no tiene receptor', () {
      // El material entra desde un proveedor, no desde un trabajador. El
      // backend rechaza un trabajadorId en una RECEPCION.
      expect(_mov('RECEPCION', 72).receptor, isNull);
    });

    test('sin RUT registrado queda solo el nombre, no una cadena rota', () {
      final despacho = _mov('DESPACHO', 12, receptorNombre: 'Javier Ortiz');
      expect(despacho.receptor, 'Javier Ortiz');
    });
  });

  group('Saldo reconstruido en la app', () {
    /// La app calcula el stock igual que el backend: sumando los movimientos
    /// con su signo. Este test fija esa equivalencia — si dejaran de coincidir,
    /// la pantalla mostraría un saldo que el servidor no reconoce.
    double saldo(List<MovimientoKardex> movimientos) =>
        movimientos.fold(0, (total, m) => total + m.cantidadConSigno);

    test('recepción menos despacho', () {
      expect(saldo([_mov('RECEPCION', 72), _mov('DESPACHO', 36)]), 36);
    });

    test('sin movimientos el saldo es cero, no desconocido', () {
      expect(saldo([]), 0);
    });

    test('el consumo también descuenta', () {
      expect(
        saldo([
          _mov('RECEPCION', 100),
          _mov('DESPACHO', 28),
          _mov('CONSUMO', 4),
        ]),
        68,
      );
    });
  });

  group('Criticidad', () {
    test('bajo el mínimo es crítico', () {
      final item = MaterialConStock(material: _material(), stock: 36);
      expect(item.critico, isTrue);
      expect(item.bajo, isFalse, reason: 'crítico y bajo se excluyen');
    });

    test('justo en el mínimo todavía no es crítico', () {
      // El mínimo es el piso aceptable, no el punto de alarma.
      final item = MaterialConStock(material: _material(), stock: 40);
      expect(item.critico, isFalse);
      expect(item.bajo, isTrue);
    });

    test('sobre el margen del 25 % no es ni crítico ni bajo', () {
      final item = MaterialConStock(material: _material(), stock: 51);
      expect(item.critico, isFalse);
      expect(item.bajo, isFalse);
    });

    test('ordena primero lo que hay que reponer', () {
      final items = [
        MaterialConStock(material: _material(), stock: 90),
        MaterialConStock(material: _material(), stock: 36),
        MaterialConStock(material: _material(), stock: 45),
      ]..sort((a, b) => a.criticidad.compareTo(b.criticidad));

      expect(items.map((i) => i.stock).toList(), [36, 45, 90]);
    });
  });

  group('Formato chileno', () {
    test('los miles se separan con punto y los decimales con coma', () {
      // "1,240" en una bodega chilena se lee mil doscientos cuarenta.
      expect(Formato.cantidad(1240), '1.240');
      expect(Formato.cantidad(2.5), '2,5');
    });

    test('las cantidades enteras no arrastran decimales', () {
      expect(Formato.cantidad(36), '36');
    });

    test('el signo del movimiento usa el menos tipográfico', () {
      expect(Formato.cantidadConSigno(72), '+72');
      expect(Formato.cantidadConSigno(-36), '−36');
    });

    test('los pesos van sin decimales', () {
      expect(Formato.pesos(5980), r'$5.980');
    });
  });
}
