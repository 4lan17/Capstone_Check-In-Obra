import 'package:flutter_riverpod/flutter_riverpod.dart';

/// La hora de ahora. Es un provider para que las pruebas la controlen: lo que
/// depende del paso del tiempo (un código que vence a los dos minutos) no se
/// puede probar esperando.
final relojProvider = Provider<DateTime Function()>((ref) => DateTime.now);
