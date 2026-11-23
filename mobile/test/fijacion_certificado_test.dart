import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:checkinobra_mobile/core/network/api_client.dart';
import 'package:checkinobra_mobile/core/network/app_config.dart';
import 'package:checkinobra_mobile/core/network/errores.dart';
import 'package:checkinobra_mobile/core/network/fijacion_certificado.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';

/// Una huella "de mentira" pero bien formada: 32 bytes en hexadecimal.
String _huella(int relleno) => List.filled(
  32,
  relleno,
).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _der(String texto) => Uint8List.fromList(utf8.encode(texto));

String _sha256(Uint8List bytes) => sha256.convert(bytes).toString();

void main() {
  group('Sin la variable no hace nada', () {
    test('sin definición no hay fijación', () {
      expect(FijacionCertificado.desde(null), isNull);
      expect(FijacionCertificado.desde(''), isNull);
      expect(FijacionCertificado.desde('   '), isNull);
      expect(FijacionCertificado.desde(' , ,'), isNull);
    });

    test('la configuración de la app sin la variable queda sin fijación', () {
      // El desarrollo y el emulador no pasan --dart-define=API_CERT_SHA256.
      expect(AppConfig.fijacion, isNull);
      expect(AppConfig.errorDeConfiguracion, isNull);
    });

    test('el cliente HTTP sin fijación es el de siempre', () {
      final cliente = ApiClient();

      // El adaptador por defecto: sin cliente propio que decida los
      // certificados.
      final adaptador = cliente.dio.httpClientAdapter as IOHttpClientAdapter;
      expect(adaptador.createHttpClient, isNull);
      expect(adaptador.validateCertificate, isNull);
    });
  });

  group('La huella', () {
    test('coincide cuando es el SHA-256 del certificado', () {
      final cert = _der('certificado del servidor');
      final fijacion = FijacionCertificado.desde(_sha256(cert))!;

      expect(fijacion.acepta(cert), isTrue);
    });

    test('no coincide con otro certificado', () {
      final fijacion = FijacionCertificado.desde(
        _sha256(_der('certificado del servidor')),
      )!;

      expect(fijacion.acepta(_der('certificado de un impostor')), isFalse);
    });

    test('con varias huellas acepta cualquiera de ellas', () {
      final actual = _der('certificado actual');
      final proximo = _der('certificado de la renovación');
      final fijacion = FijacionCertificado.desde(
        '${_sha256(actual)}, ${_sha256(proximo)}',
      )!;

      expect(fijacion.acepta(actual), isTrue);
      expect(fijacion.acepta(proximo), isTrue);
      expect(fijacion.acepta(_der('otro')), isFalse);
    });

    test('acepta el formato de openssl: mayúsculas y dos puntos', () {
      final cert = _der('certificado del servidor');
      final hex = _sha256(cert).toUpperCase();
      final conPuntos = [
        for (var i = 0; i < hex.length; i += 2) hex.substring(i, i + 2),
      ].join(':');

      expect(FijacionCertificado.desde(conPuntos)!.acepta(cert), isTrue);
      expect(FijacionCertificado.desde(hex)!.acepta(cert), isTrue);
    });

    test('una huella mal formada es un error de configuración, no un '
        'silencio', () {
      // Ignorarla dejaría la app sin fijar creyendo que está fijada.
      for (final mala in ['abc123', 'z' * 64, _huella(1).substring(2)]) {
        expect(
          () => FijacionCertificado.desde(mala),
          throwsA(isA<ConfiguracionInvalida>()),
          reason: mala,
        );
      }
    });

    test('una huella mala entre varias buenas también falla', () {
      expect(
        () => FijacionCertificado.desde('${_huella(1)},corta'),
        throwsA(isA<ConfiguracionInvalida>()),
      );
    });

    test('el mensaje dice qué hacer', () {
      try {
        FijacionCertificado.desde('corta');
        fail('debía fallar');
      } on ConfiguracionInvalida catch (e) {
        expect(e.mensaje, contains('API_CERT_SHA256'));
        expect(e.mensaje, contains('64'));
      }
    });
  });

  group('Con un servidor TLS de verdad', () {
    late Directory carpeta;
    late HttpServer servidor;
    late String huellaDelServidor;
    var sePuedeProbar = true;
    var peticiones = 0;

    setUpAll(() async {
      carpeta = Directory.systemTemp.createTempSync('fijacion_');
      // El certificado se genera acá y no se versiona: una clave privada de
      // prueba en el repositorio dispararía a cualquier escáner de secretos.
      final gen = await Process.run('openssl', [
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-days',
        '2',
        '-subj',
        '/CN=localhost',
        '-keyout',
        '${carpeta.path}/clave.pem',
        '-out',
        '${carpeta.path}/cert.pem',
      ]);
      if (gen.exitCode != 0) {
        sePuedeProbar = false;
        return;
      }
      // La misma línea que el README le pide al equipo que corra.
      final huella = await Process.run('openssl', [
        'x509',
        '-in',
        '${carpeta.path}/cert.pem',
        '-noout',
        '-fingerprint',
        '-sha256',
      ]);
      huellaDelServidor = (huella.stdout as String).trim().split('=').last;

      final contexto = SecurityContext()
        ..useCertificateChain('${carpeta.path}/cert.pem')
        ..usePrivateKey('${carpeta.path}/clave.pem');
      servidor = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        contexto,
      );
      servidor.listen((peticion) {
        peticiones++;
        peticion.response
          ..headers.contentType = ContentType.json
          ..write('{"ok":true}');
        peticion.response.close();
      });
    });

    tearDownAll(() async {
      if (!sePuedeProbar) return;
      await servidor.close(force: true);
      carpeta.deleteSync(recursive: true);
    });

    Dio clienteCon(String? definicion) {
      final dio = Dio(
        BaseOptions(baseUrl: 'https://localhost:${servidor.port}'),
      );
      final fijacion = FijacionCertificado.desde(definicion);
      if (fijacion != null) {
        dio.httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: fijacion.crearHttpClient,
        );
      }
      return dio;
    }

    test('con la huella del servidor, conecta', () async {
      if (!sePuedeProbar) return markTestSkipped('no hay openssl');

      final r = await clienteCon(huellaDelServidor).get<dynamic>('/');

      expect(r.statusCode, 200);
    });

    test(
      'con la huella de otro certificado, se rechaza antes de hablar',
      () async {
        if (!sePuedeProbar) return markTestSkipped('no hay openssl');

        // El servidor cuenta cada petición que le llega: si la fijación fallara
        // tarde, el PIN ya habría viajado.
        final antes = peticiones;

        await expectLater(
          clienteCon(_huella(7)).get<dynamic>('/'),
          throwsA(isA<DioException>()),
        );
        expect(peticiones, antes);
      },
    );

    test('sin fijación, un certificado que el sistema no conoce igual se '
        'rechaza (comportamiento de siempre)', () async {
      if (!sePuedeProbar) return markTestSkipped('no hay openssl');

      await expectLater(
        clienteCon(null).get<dynamic>('/'),
        throwsA(isA<DioException>()),
      );
    });

    test('con varias huellas conecta si una es la del servidor', () async {
      if (!sePuedeProbar) return markTestSkipped('no hay openssl');

      final r = await clienteCon('${_huella(1)},$huellaDelServidor')
          .get<dynamic>('/');

      expect(r.statusCode, 200);
    });

    test(
      'el rechazo llega como certificado inválido, con su mensaje',
      () async {
        if (!sePuedeProbar) return markTestSkipped('no hay openssl');

        // El cliente real de la app traduce el fallo del handshake a
        // `badCertificate`, que `errores.dart` ya explica.
        final dio = clienteCon(_huella(7));
        ApiClient.traducirFallosDeCertificado(dio);

        try {
          await dio.get<dynamic>('/');
          fail('debía rechazar');
        } on DioException catch (e) {
          expect(e.type, DioExceptionType.badCertificate);
          expect(mensajeDeError(e), contains('certificado'));
        }
      },
    );
  });
}
