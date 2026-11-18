/// Identidad de dispositivo registrada igual que en la app móvil.
///
/// El portal TV solo acepta `sn` que ya existen en su base de datos: con un
/// `sn` inventado responde `aaa100080` («snToken inválido») y la sesión única
/// por cuenta (`aaa100083`) impide usar la misma cuenta en dos equipos.
///
/// La app móvil (`com.xuper.wiwyxuper.mobile`) registra un dispositivo nuevo
/// con `v3/snToken` y `v8/active`; si la huella es desconocida responde
/// `isNew=0` y el cliente calcula `sn = md5(snToken + sal)`. Ese `sn` ya es
/// aceptado por el portal TV y cada instalación obtiene su propia cuenta, así
/// que dos equipos pueden reproducir a la vez sin robarse la sesión.
///
/// Todo se reproduce aquí sin APK, sin Frida y sin pasos manuales.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'wiwy_des.dart';

/// Datos del dispositivo fijo que usaba NexusStream antes de registrar uno
/// propio. Se conserva como respaldo si el registro no está disponible.
abstract final class WiwyLegacy {
  static const String sn = '1798e621bbde68b9cf944375d862af41';
  static const String macAddr = '8c:fd:f0:c7:28:44';
}

/// Identidad persistida por instalación.
class WiwyIdentity {
  const WiwyIdentity({
    required this.sn,
    required this.macAddr,
    this.snToken = '',
    this.userId = '',
    this.androidId = '',
    this.registered = false,
  });

  /// Identidad anterior: la cuenta «pagada» que compartían todas las copias.
  static const WiwyIdentity legacy = WiwyIdentity(
    sn: WiwyLegacy.sn,
    macAddr: WiwyLegacy.macAddr,
  );

  /// Nombre del archivo dentro de [WiwyStore].
  static const String storageName = 'wiwy_identity_v1.json';

  final String sn;
  final String macAddr;
  final String snToken;
  final String userId;
  final String androidId;

  /// `true` si la identidad la creó este flujo (no la fija de respaldo).
  final bool registered;

  bool get isLegacy => !registered;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': 1,
    'sn': sn,
    'macAddr': macAddr,
    'snToken': snToken,
    'userId': userId,
    'androidId': androidId,
    'registered': registered,
  };

  String encode() => jsonEncode(toJson());

  static WiwyIdentity? tryParse(String raw) {
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      final sn = '${data['sn'] ?? ''}'.trim();
      final mac = '${data['macAddr'] ?? ''}'.trim();
      if (sn.isEmpty || mac.isEmpty) return null;
      return WiwyIdentity(
        sn: sn,
        macAddr: mac,
        snToken: '${data['snToken'] ?? ''}',
        userId: '${data['userId'] ?? ''}',
        androidId: '${data['androidId'] ?? ''}',
        registered: data['registered'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Error del registro de dispositivo (no del portal TV).
class WiwyIdentityException implements Exception {
  WiwyIdentityException(this.code, [this.message = '']);

  final String code;
  final String message;

  @override
  String toString() =>
      'WiwyIdentityException($code): '
      '${message.replaceAll('Wiwy', 'Servidor')}';
}

/// Registra un `sn` nuevo replicando el arranque de la app móvil.
class WiwyIdentityRegistry {
  WiwyIdentityRegistry({
    required http.Client client,
    this.timeout = const Duration(seconds: 30),
    this.logger,
    // El campo es privado; un formal inicializador obligaría a nombrar el
    // parámetro `_client:` en las llamadas.
    // ignore: prefer_initializing_formals
  }) : _client = client;

  final http.Client _client;
  final Duration timeout;
  final void Function(String message)? logger;

  /// Hosts del portal móvil (el segundo es el de respaldo del APK).
  static const List<String> hosts = [
    'https://eaeylu.bvsvfb8c.com',
    'https://c2tgd.izvhrdcjb.com',
  ];

  static const String appId = 'com.msandroid.mobile';
  static const String apkVersion = '60291';
  static const String sysVersion = '9';
  static const String reserve1 =
      '415a7a38593161756952496a4c774b665541477051513d3d';

  /// Sal que la app añade al `snToken` antes del MD5 (`la.m.c`).
  static const String snSalt = 'ntFT65w6itH!lHCPw7D=@qnsFC5adD28';

  /// Clave DESede del APK (`d5.a.j()`, UUID en Base64 con `-`→`/`, 24 bytes).
  static const String keyHex =
      'e9c7f6e7cf5bfdddb57bfe1f6dfffc6dfdbf777e3adfae1b';

  static List<int> get key => [
    for (var i = 0; i < keyHex.length; i += 2)
      int.parse(keyHex.substring(i, i + 2), radix: 16),
  ];

  static const Map<String, String> headers = {
    'Cache-Control': 'no-store;Content-type:application/json;charset=utf-8',
    'Content-Type': 'application/json;charset=utf-8',
    'apk': appId,
    'apkVer': apkVersion,
    'spkgVer': sysVersion,
    'User-Agent': 'okhttp/3.12.12',
    'Accept-Encoding': 'identity',
  };

  /// Calcula el `sn` que usa la app cuando `isNew=0`.
  static String snFromToken(String snToken) =>
      md5.convert(utf8.encode('$snToken$snSalt')).toString();

  /// Genera una identidad nueva y la deja activada en el portal móvil.
  Future<WiwyIdentity> register() async {
    final androidId = _randomHex(8);
    final mac = _randomMac();
    final tokenData = await _post(
      '/api/portalCore/v3/snToken',
      _snTokenBody(androidId, mac),
    );

    final snToken = '${tokenData['snToken'] ?? ''}'.trim();
    if (snToken.isEmpty) {
      throw WiwyIdentityException('snToken', 'respuesta sin snToken');
    }

    final isNew = '${tokenData['isNew'] ?? ''}';
    final serverSn = '${tokenData['sn'] ?? ''}'.trim();
    final sn = isNew == '1' && serverSn.isNotEmpty
        ? serverSn
        : snFromToken(snToken);

    final active = await _post('/api/portalCore/v8/active', <String, dynamic>{
      'channel': 'default',
      'macAddr': mac.toUpperCase(),
      'snToken': snToken,
      ..._common(sn),
    });
    final userId = '${active['userId'] ?? ''}'.trim();
    _log('registrado sn=$sn userId=$userId');

    return WiwyIdentity(
      sn: sn,
      macAddr: mac.toUpperCase(),
      snToken: snToken,
      userId: userId,
      androidId: androidId,
      registered: true,
    );
  }

  Map<String, dynamic> _snTokenBody(String androidId, String mac) =>
      <String, dynamic>{
        'androidId': androidId,
        'board': 'SM8850\u2011AC',
        'brand': 'Nubia',
        'cpuAbi': 'arm64-v8a',
        'cpuId': '',
        'device': 'NX809J',
        'diskInfo': '',
        'display': 'Nubia-user 9.0.0 20171130.276299 release-keys',
        'etheMac': '02:00:00:00:00:00',
        'fingerprint': 'Nubia/Nubia/NX809J:9/dev03041042:user/release-keys',
        'gatewayMac': '02:00:00:00:01:00',
        'hardware': 'intel',
        'host': 'dev',
        'manufacturer': 'Nubia',
        'ramSize': '6,24 GB',
        'romSize': '34,57 GB',
        'se': '66:60:94:16:9B:B9:F5:25:0C:BE:C8:BE:2C:0C:09:7E:83:47:18:87',
        'serialNumber': 'unknown',
        'tags': 'release-keys',
        'verId': 'PI',
        'wifiMac': mac,
        ..._common(''),
      };

  Map<String, dynamic> _common(String sn) => <String, dynamic>{
    'loginType': '3',
    'appLanguage': 'es',
    'apkVersion': apkVersion,
    'sysVersion': sysVersion,
    'appId': appId,
    'hardwareInfo': 'intel',
    'model': 'NX809J',
    'product': 'NX809J',
    'cpu': 'arm64-v8a',
    'deviceToken': 'dxpNLCToQnCBYDQ6Ko0EEI',
    'reserve1': reserve1,
    'sn': sn,
    'drmId': '',
  };

  /// Envía el cuerpo cifrado como el APK y devuelve el `data` descifrado.
  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final body = encryptLikeApp(jsonEncode(payload), key);
    Object? lastError;
    for (final host in hosts) {
      final uri = Uri.parse('$host$path');
      try {
        final response = await _client
            .post(uri, headers: headers, body: body)
            .timeout(timeout);
        final text = utf8.decode(response.bodyBytes, allowMalformed: true);
        if (response.statusCode != 200) {
          lastError = WiwyIdentityException('http${response.statusCode}', text);
          _log('HTTP ${response.statusCode} en $uri');
          continue;
        }
        final outer = jsonDecode(text);
        if (outer is! Map) {
          lastError = WiwyIdentityException('badjson', 'respuesta no es mapa');
          continue;
        }
        final code = '${outer['returnCode'] ?? '?'}';
        if (code != '0') {
          lastError = WiwyIdentityException(code, '${outer['errorMessage']}');
          _log('portal $code en $uri: ${outer['errorMessage']}');
          continue;
        }
        final data = outer['data'];
        if (data is! String || data.isEmpty) return <String, dynamic>{};
        final decoded = jsonDecode(decryptLikeApp(data, key));
        return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      } on TimeoutException catch (error) {
        lastError = WiwyIdentityException('timeout', '$error');
        _log('timeout en $uri');
      } catch (error) {
        lastError = error;
        _log('error en $uri: $error');
      }
    }
    if (lastError is WiwyIdentityException) throw lastError;
    throw WiwyIdentityException('network', '$lastError');
  }

  static String _randomHex(int bytes) {
    final random = Random.secure();
    return [
      for (var i = 0; i < bytes; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  static String _randomMac() {
    final random = Random.secure();
    final bytes = [for (var i = 0; i < 6; i++) random.nextInt(256)];
    bytes[0] = (bytes[0] & 0xfc) | 0x02; // MAC local, sin multicast
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
  }

  void _log(String message) => logger?.call(message);
}
