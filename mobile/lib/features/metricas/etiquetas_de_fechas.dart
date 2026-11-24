import 'package:intl/intl.dart';

/// Las etiquetas del eje horizontal de una serie por fecha, según de qué
/// tamaño es cada punto:
/// * `DIA`: la inicial del día de la semana si caben siete (`L M X J V S D`);
///   si son más, el número del día.
/// * `SEMANA`: «16 nov».
/// * `MES`: «nov».
List<String> etiquetasDeFechas(List<DateTime?> fechas, String granularidad) {
  const iniciales = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
  final dia = DateFormat('d', 'es_CL');
  final semana = DateFormat('d MMM', 'es_CL');
  final mes = DateFormat('MMM', 'es_CL');
  return [
    for (final f in fechas)
      if (f == null)
        ''
      else
        switch (granularidad.toUpperCase()) {
          'SEMANA' => semana.format(f),
          'MES' => mes.format(f),
          _ => fechas.length <= 7 ? iniciales[f.weekday - 1] : dia.format(f),
        },
  ];
}
