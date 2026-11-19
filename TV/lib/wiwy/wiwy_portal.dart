/// Cliente del portal de WiwyXuper, Dart puro.
///
/// Reproduce el protocolo del APK sin emulador, sin APK y sin Frida:
///
/// ```text
/// POST /api/portalCore/v8/active        -> userId + userToken
/// POST /api/portalCore/v15/getSlbInfo   -> cdn_list con Content-Auth
/// POST /api/portalCore/v6/getLiveData   -> canales + Content-License
/// ```
///
/// Todo el cuerpo va cifrado con `wiwy_des.dart` y se necesitan las cabeceras
/// de versión del APK (`apk`, `apkVer`, `spkgVer`); sin ellas el portal
/// responde `portal200001 "版本已停止使用"`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/channel.dart';
import '../services/proxy_service.dart';
import 'wiwy_des.dart';
import 'wiwy_identity.dart';

// ---------------------------------------------------------------- parámetros

/// Valores estáticos extraídos del APK y de capturas reales del portal.
abstract final class WiwyConfig {
  /// Clave DESede (24 bytes) usada para cifrar y descifrar.
  static const String keyHex =
      'e7af1ed7de1ffddd7bd3fe37ebdffde9ef3fe1ae39edfeb8';

  static List<int> get key => [
    for (var i = 0; i < keyHex.length; i += 2)
      int.parse(keyHex.substring(i, i + 2), radix: 16),
  ];

  /// Clave del servicio de subtítulos del APK, codificada en Base64.
  static const String subtitleKeyBase64 = 'NxZZ7EYgaJiJSBHjnq7sDxYvYRm32tPQ';

  static List<int> get subtitleKey => base64.decode(subtitleKeyBase64);

  /// Portal principal y alternativo (se prueban en orden).
  static const List<String> portals = [
    'https://brkhzs.udigkkrc.com',
    'https://eslitx.7jpeq68c.com',
  ];

  /// Cabeceras obligatorias: son las que validan la versión del cliente.
  ///
  /// `apkVer` debe ser exactamente `43404`: el portal responde
  /// `portal200001` («versión detenida») con cualquier otro valor, incluso
  /// versiones más nuevas. No cambiar sin volver a verificar con el portal.
  ///
  /// Algunos televisores (Android 9 / Leanback) son los únicos a los que el
  /// CDN responde `portal200001` (por ejemplo al abrir Cine). En ese caso se
  /// reintenta con [tvFallbackHeaders]: se mantiene `apkVer` pero se normalizan
  /// `User-Agent` y `Cache-Control`, que son los campos que esos modelos
  /// reescriben. Se conserva `identity` para que `dart:io` no tenga que
  /// descomprimir la respuesta (el cliente `http` no lo hace por nosotros).
  static Map<String, String> get tvFallbackHeaders => <String, String>{
    ...headers,
    'Cache-Control': 'no-store',
    'User-Agent': 'Dalvik/2.1.0 (Linux; U; Android 9; NX809J Build/PKQ1.190616.001)',
  };
  static const Map<String, String> headers = {
    'Cache-Control': 'no-store;Content-type:application/json;charset=utf-8',
    'apk': 'com.android.msandroid',
    'apkVer': '43404',
    'spkgVer': '2022-05-25 14:15:32_28_9_4.19.71+',
    'Content-Type': 'application/json; charset=utf-8',
    'User-Agent': 'okhttp/3.12.12',
    'Accept-Encoding': 'identity',
  };

  /// Bloque de dispositivo que el APK añade a todas las peticiones.
  ///
  /// [sn] permite usar el serial registrado por esta instalación (ver
  /// `wiwy_identity.dart`); sin él se usa el serial fijo histórico.
  static Map<String, dynamic> device({String? sn}) => <String, dynamic>{
    'loginType': '2',
    'appLanguage': 'es',
    'apkVersion': '43665',
    'sysVersion': '2022-05-25 14:15:32_28_9_4.19.71+',
    'appId': 'com.android.msandroid',
    'hardwareInfo': 'intel',
    'model': 'NX809J',
    'product': 'NX809J',
    'cpu': 'arm64-v8a',
    'B29': '',
    'reserve1': '415a7a38593161756952496a4c774b665541477051513d3d',
    'deviceToken': 'cZzJOEsFQhGpPQBEKyFn3q:APA91bGsow1LjJe1AD4E1WoztkCwYC770cWkOtkiNdDVKyYY1X9DoOUC6graIhUKFbhvfTE7YkRfOyNd3yNdocwNQRd2tXbhu0caHeMaAO7ntchauLDuH0U',
    'sn': sn ?? WiwyLegacy.sn,
    'drmId': '',
    'sdkVer': 28,
  };

  /// Serial del "dispositivo" histórico (cuenta compartida por todas las
  /// copias). Se conserva solo como respaldo del registro por instalación.
  static const String legacySn = WiwyLegacy.sn;
  static const String legacyMacAddr = WiwyLegacy.macAddr;
  static const String portalCode = 'masnew';
  static const String userIdentity = '1';

  /// Columnas del portal: general (≈1000 canales) y principal (141).
  static const List<int> columns = [76182, 77970];

  /// Cabeceras que exige el CDN al reproducir.
  static const String playerUserAgent = 'Ranger/4.9.4-17294ac0';
  static const String playerApp = 'com.android.msandroid';
  static const String playerAppVersion = '43665';
  static const String playerPragma = 'akamai-x-cache-on';
  static const String playerBuffer = '0';

  /// Tipos de CDN por orden de preferencia (4 sirve todos los canales).
  static const List<int> preferCdnTypes = [4, 1];
}

// ------------------------------------------------------------------- modelos

class WiwyException implements Exception {
  WiwyException(this.code, [this.message = '']);

  final String code;
  final String message;

  @override
  String toString() =>
      'WiwyException($code): ${message.replaceAll('Wiwy', 'Servidor')}';
}

class WiwySession {
  const WiwySession({
    required this.userId,
    required this.userToken,
    this.tips = '',
  });

  final String userId;
  final String userToken;
  final String tips;

  bool get isValid => userId.isNotEmpty && userToken.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'userToken': userToken,
    'tips': tips,
  };

  static WiwySession fromJson(Map<String, dynamic> json) => WiwySession(
    userId: '${json['userId'] ?? ''}',
    userToken: '${json['userToken'] ?? ''}',
    tips: '${json['tips'] ?? ''}',
  );
}

/// Entrada de `cdn_list` con el `Content-Auth` ya listo para usar.
class WiwyCdn {
  const WiwyCdn({
    required this.type,
    required this.host,
    required this.auth,
    required this.tag,
  });

  final int type;
  final String host;
  final String auth;
  final String tag;

  /// Momento en que caduca el `Content-Auth` (según su parámetro `expired`).
  DateTime? get expiresAt {
    for (final part in auth.split('&')) {
      if (part.startsWith('expired=')) {
        final value = int.tryParse(part.substring('expired='.length));
        if (value != null) {
          return DateTime.fromMillisecondsSinceEpoch(value * 1000);
        }
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'host': host,
    'auth': auth,
    'tag': tag,
  };

  static WiwyCdn fromJson(Map<String, dynamic> json) => WiwyCdn(
    type: int.tryParse('${json['type']}') ?? 0,
    host: '${json['host'] ?? ''}',
    auth: '${json['auth'] ?? ''}',
    tag: '${json['tag'] ?? ''}',
  );
}

/// Datos de `getSlbInfo` que interesan a la app.
class WiwySlbInfo {
  const WiwySlbInfo({required this.cdns, required this.raw});

  final List<WiwyCdn> cdns;
  final Map<String, dynamic> raw;

  /// CDNs de directo agrupados por tipo, en orden de preferencia.
  List<WiwyCdn> get liveCdns {
    final live = cdns
        .where((c) => c.tag == 'live' && c.host.isNotEmpty)
        .toList();
    live.sort((a, b) {
      final ai = WiwyConfig.preferCdnTypes.indexOf(a.type);
      final bi = WiwyConfig.preferCdnTypes.indexOf(b.type);
      return (ai < 0 ? 99 : ai).compareTo(bi < 0 ? 99 : bi);
    });
    return live;
  }

  /// CDNs de vídeo bajo demanda (películas y series).
  List<WiwyCdn> get vodCdns =>
      cdns.where((c) => c.tag == 'vod' && c.host.isNotEmpty).toList();

  /// Caducidad más temprana entre los CDN de directo.
  DateTime? get expiresAt {
    DateTime? earliest;
    for (final cdn in liveCdns) {
      final exp = cdn.expiresAt;
      if (exp == null) continue;
      if (earliest == null || exp.isBefore(earliest)) earliest = exp;
    }
    return earliest;
  }
}

/// Canal tal como lo entrega `getLiveData` (solo lo que usamos).
class WiwyChannelData {
  const WiwyChannelData({
    required this.name,
    required this.channelCode,
    required this.channelNumber,
    required this.logo,
    required this.playCode,
    required this.cdnType,
    required this.license,
  });

  final String name;
  final String channelCode;
  final String channelNumber;
  final String logo;
  final String playCode;
  final int cdnType;
  final String license;

  static WiwyChannelData? fromJson(Map<String, dynamic> json) {
    final name = '${json['name'] ?? json['alias'] ?? ''}'.trim();
    final addresses = (json['liveAddressList'] as List?) ?? const [];
    final entries = addresses.whereType<Map>().toList();
    if (name.isEmpty || entries.isEmpty) return null;

    // Preferimos el CDN de tipo 4 (el único que sirve desde el PC).
    Map? chosen;
    for (final type in WiwyConfig.preferCdnTypes.where((t) => t != 1)) {
      for (final entry in entries) {
        if ('${entry['cdnType']}' == '$type') {
          chosen = entry;
          break;
        }
      }
      if (chosen != null) break;
    }
    chosen ??= entries.first;

    final playCode = '${chosen['playCode'] ?? ''}'.trim();
    if (playCode.isEmpty) return null;

    return WiwyChannelData(
      name: name,
      channelCode: '${json['channelCode'] ?? playCode}'.trim(),
      channelNumber: '${json['channelNumber'] ?? ''}'.trim(),
      logo: '${json['posterUrl'] ?? ''}'.trim(),
      playCode: playCode,
      cdnType: int.tryParse('${chosen['cdnType']}') ?? 0,
      license: '${chosen['license'] ?? ''}',
    );
  }
}

// ------------------------------------------------------------------- cliente

/// Cliente HTTP del portal. Es *stateless*: recibe y devuelve datos.
class WiwyPortal {
  WiwyPortal({
    http.Client? client,
    this.timeout = const Duration(seconds: 45),
    this.portalIndex = 0,
    this.logger,
    WiwyIdentity? identity,
  }) : _client = client ?? ProxySettings.instance.createClient(),
       identity = identity ?? WiwyIdentity.legacy;

  http.Client _client;
  final Duration timeout;
  final int portalIndex;
  final void Function(String message)? logger;

  /// Serial y MAC con los que se activa la sesión. `WiwySource` lo sustituye
  /// por la identidad registrada de esta instalación en cuanto la resuelve.
  WiwyIdentity identity;

  /// Cliente HTTP del portal (el registro de identidad reutiliza la conexión).
  http.Client get client => _client;

  void _log(String message) => logger?.call(message);

  /// Recrea el cliente para aplicar un cambio de VPN/proxy.
  void resetClient() {
    try {
      _client.close();
    } catch (_) {
      // El cliente anterior puede estar ya cerrado.
    }
    _client = ProxySettings.instance.createClient();
  }

  void close() => _client.close();

  // -- transporte ---------------------------------------------------------

  /// Envía la petición y, si el portal responde `portal200001` con las
  /// cabeceras habituales, la repite una vez con las cabeceras alternativas
  /// que aceptan los Android TV. Sin esto, Cine no abre en esos dispositivos
  /// aunque el resto de la app (canales) funcione.
  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    try {
      return await _postRaw(path, payload);
    } on WiwyException catch (error) {
      if (error.code != 'portal200001') rethrow;
      _log('portal200001 en $path; reintentando con cabeceras de TV');
      return _postRaw(path, payload, WiwyConfig.tvFallbackHeaders);
    }
  }

  Future<Map<String, dynamic>> _postRaw(
    String path,
    Map<String, dynamic> payload, [
    Map<String, String>? headersOverride,
  ]) async {
    final body = encryptLikeApp(jsonEncode(payload), WiwyConfig.key);
    final order = <String>[
      WiwyConfig.portals[portalIndex % WiwyConfig.portals.length],
      ...WiwyConfig.portals.where(
        (p) => p != WiwyConfig.portals[portalIndex % WiwyConfig.portals.length],
      ),
    ];

    Object? lastError;
    for (final host in order) {
      final uri = Uri.parse('$host$path');
      try {
        final response = await _client
            .post(
              uri,
              headers: headersOverride ?? WiwyConfig.headers,
              body: body,
            )
            .timeout(timeout);

        if (response.statusCode != 200) {
          lastError = WiwyException(
            'http${response.statusCode}',
            utf8.decode(response.bodyBytes, allowMalformed: true),
          );
          _log('HTTP ${response.statusCode} en $uri');
          continue;
        }

        final outer = jsonDecode(utf8.decode(response.bodyBytes));
        if (outer is! Map) {
          lastError = WiwyException('badjson', 'respuesta no es objeto');
          continue;
        }

        final code = '${outer['returnCode'] ?? '?'}';
        if (code != '0') {
          lastError = WiwyException(code, '${outer['errorMessage'] ?? ''}');
          _log('portal $code en $uri: ${outer['errorMessage'] ?? ''}');
          continue;
        }

        final data = outer['data'];
        if (data is! String || data.isEmpty) return <String, dynamic>{};

        final plain = decryptLikeApp(data, WiwyConfig.key);
        final decoded = jsonDecode(plain);
        return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      } on TimeoutException catch (error) {
        lastError = WiwyException('timeout', '$error');
        _log('timeout en $uri');
      } catch (error) {
        lastError = error;
        _log('error en $uri: $error');
      }
    }

    if (lastError is WiwyException) throw lastError;
    throw WiwyException('network', '$lastError');
  }

  /// `subs/terminal/metadata`: subtítulos externos de un título.
  ///
  /// Usa una clave distinta a la del portal y responde con un sobre JSON sin
  /// cifrar cuyo campo `data` contiene la lista cifrada (`SubTitleItemData`).
  Future<List<ChannelSubtitle>> subtitles(String programId) async {
    final id = programId.trim();
    if (id.isEmpty) return const [];

    final body = encryptLikeApp(
      jsonEncode(<String, dynamic>{'programId': id}),
      WiwyConfig.subtitleKey,
    );
    final order = <String>[
      WiwyConfig.portals[portalIndex % WiwyConfig.portals.length],
      ...WiwyConfig.portals.where(
        (p) => p != WiwyConfig.portals[portalIndex % WiwyConfig.portals.length],
      ),
    ];

    Object? lastError;
    for (final host in order) {
      final uri = Uri.parse('$host/api/subs/terminal/metadata');
      try {
        final response = await _client
            .post(uri, headers: WiwyConfig.headers, body: body)
            .timeout(timeout);

        if (response.statusCode != 200) {
          lastError = WiwyException(
            'http${response.statusCode}',
            utf8.decode(response.bodyBytes, allowMalformed: true),
          );
          continue;
        }

        final outer = jsonDecode(utf8.decode(response.bodyBytes));
        if (outer is! Map) {
          lastError = WiwyException('badjson', 'respuesta no es objeto');
          continue;
        }
        final code = '${outer['returnCode'] ?? '?'}';
        if (code != '0') {
          lastError = WiwyException(code, '${outer['errorMessage'] ?? ''}');
          _log('subtítulos $code en $uri: ${outer['errorMessage'] ?? ''}');
          continue;
        }

        final data = outer['data'];
        if (data is! String || data.isEmpty) return const [];

        Object? decoded;
        try {
          decoded = jsonDecode(decryptLikeApp(data, WiwyConfig.subtitleKey));
        } catch (_) {
          // Por si el servicio empieza a responder JSON plano.
          decoded = jsonDecode(data);
        }
        if (decoded is! List) return const [];

        final subtitles = <ChannelSubtitle>[];
        final seen = <String>{};
        for (final item in decoded) {
          if (item is! Map) continue;
          final language = '${item['language'] ?? ''}'.trim().toLowerCase();
          for (final file in (item['file'] as List?) ?? const []) {
            if (file is! Map) continue;
            final url = '${file['url'] ?? ''}'.trim();
            if (url.isEmpty || !seen.add(url)) continue;
            final format = '${file['fileType'] ?? 'srt'}'.trim().toLowerCase();
            subtitles.add(
              ChannelSubtitle(
                url: url,
                language: language,
                format: format.isEmpty ? 'srt' : format,
              ),
            );
          }
        }
        return subtitles;
      } on TimeoutException catch (error) {
        lastError = WiwyException('timeout', '$error');
      } catch (error) {
        lastError = error;
        _log('subtítulos en $uri: $error');
      }
    }

    if (lastError is WiwyException) throw lastError;
    throw WiwyException('network', '$lastError');
  }

  // -- endpoints ----------------------------------------------------------

  /// `v8/active`: devuelve un `userToken` nuevo sin credenciales.
  Future<WiwySession> activate({required int openNum}) async {
    final device = WiwyConfig.device(sn: identity.sn);
    final payload = <String, dynamic>{
      'authCode': '',
      'authVersion': '',
      'channel': 'default',
      'macAddr': identity.macAddr,
      'matadata': '',
      'openNum': openNum,
      'reserve1': device['reserve1'],
      'signdata': '',
      'snToken': '',
      ...device,
      'portalCode': '',
      'deviceToken': '',
    };

    final data = await _post('/api/portalCore/v8/active', payload);
    return WiwySession(
      userId: '${data['userId'] ?? ''}',
      userToken: '${data['userToken'] ?? ''}',
      tips: '${data['tips'] ?? ''}',
    );
  }

  /// `v15/getSlbInfo`: devuelve los CDN con `Content-Auth` fresco.
  Future<WiwySlbInfo> getSlbInfo(WiwySession session) async {
    final device = WiwyConfig.device(sn: identity.sn)..remove('B29');
    final payload = <String, dynamic>{
      'appParams': '',
      'appVer': '43665',
      'encMediaSupported': 1,
      'hasPay': '0',
      'lang': 'es',
      'liveCodeList': ['masnew_live'],
      'pipFlag': '0',
      'portalCode': WiwyConfig.portalCode,
      'reserve1': device['reserve1'],
      'type': 'merge',
      'userId': session.userId,
      'userIdentity': WiwyConfig.userIdentity,
      'userToken': session.userToken,
      ...device,
    };

    final data = await _post('/api/portalCore/v15/getSlbInfo', payload);
    final cdns = <WiwyCdn>[];
    for (final item in (data['cdn_list'] as List?) ?? const []) {
      if (item is! Map) continue;
      final main = '${item['main_addr'] ?? ''}'.trim();
      if (main.isEmpty) continue;
      final host = main
          .replaceFirst('https://', '')
          .replaceFirst('http://', '')
          .split('/')
          .first;
      final urls = (item['url_list'] as List?) ?? const [];
      final auth = urls.isEmpty || urls.first is! Map
          ? ''
          : '${(urls.first as Map)['url'] ?? ''}';
      cdns.add(
        WiwyCdn(
          type: int.tryParse('${item['cdn_type']}') ?? 0,
          host: host,
          auth: auth,
          tag: '${item['tag'] ?? ''}',
        ),
      );
    }
    return WiwySlbInfo(cdns: cdns, raw: data);
  }

  // -- catálogo VOD -------------------------------------------------------

  /// Cuerpo común de las peticiones de catálogo (películas y series).
  Map<String, dynamic> _vodBody(WiwySession session) => <String, dynamic>{
    'portalCode': WiwyConfig.portalCode,
    'userId': session.userId,
    'userToken': session.userToken,
    'loginType': '2',
    ...WiwyConfig.device(sn: identity.sn),
  };

  /// `v3/getShelveData`: estantería (lista) de una columna VOD.
  ///
  /// El portal solo devuelve datos con `columnType` "2".
  Future<Map<String, dynamic>> getShelveData(
    WiwySession session,
    int columnId, {
    int page = 1,
    int pageSize = 100,
  }) {
    return _post('/api/portalCore/v3/getShelveData', <String, dynamic>{
      ..._vodBody(session),
      'columnId': columnId,
      'columnType': '2',
      'encryptVersion': 1,
      'numDisplay': 0,
      'pageNum': page,
      'pageSize': pageSize,
    });
  }

  /// `v3/searchByName`: búsqueda global en el catálogo (películas y series).
  ///
  /// `columnId` -1 y `type` "1" es lo que usa la app original para buscar
  /// en todo el portal, no solo en una columna.
  Future<Map<String, dynamic>> searchByName(
    WiwySession session,
    String value, {
    int page = 1,
    int pageSize = 20,
  }) {
    return _post('/api/portalCore/v3/searchByName', <String, dynamic>{
      ..._vodBody(session),
      'columnId': '-1',
      'value': value,
      'type': '1',
      'pageSize': pageSize,
      'pageNum': page,
      'filter': '',
    });
  }

  /// `v4/getItemData`: ficha completa (sinopsis, reparto, episodios).
  Future<Map<String, dynamic>> getItemData(
    WiwySession session, {
    required int columnId,
    required String contentId,
    required String type,
  }) {
    return _post('/api/portalCore/v4/getItemData', <String, dynamic>{
      ..._vodBody(session),
      'columnId': columnId,
      'contentId': contentId,
      'type': type,
    });
  }

  /// `v10/startPlayVOD`: devuelve la media real (media_code + licencia).
  ///
  /// En series [contentId] es el capítulo y [seriesContentId] la serie.
  Future<Map<String, dynamic>> startPlayVod(
    WiwySession session, {
    required int columnId,
    required String contentId,
    String seriesContentId = '',
    required String type,
    int startTime = 0,
    String authType = '',
    List<int> episodeNumbers = const [1],
  }) {
    return _post('/api/portalCore/v10/startPlayVOD', <String, dynamic>{
      ..._vodBody(session),
      'columnId': columnId,
      'contentId': contentId,
      'seriesContentId': seriesContentId,
      'type': type,
      'startTime': startTime,
      'authType': authType,
      'episodeNumberList': episodeNumbers,
    });
  }

  /// `v6/getLiveData`: canales de una columna.
  Future<List<WiwyChannelData>> getLiveData(
    int columnId,
    WiwySession session,
  ) async {
    final payload = <String, dynamic>{
      'columnId': columnId,
      'isAv1': '0',
      'pageNum': 1,
      'pageSize': 1000,
      'portalCode': WiwyConfig.portalCode,
      'specialFlag': '0',
      'userId': session.userId,
      'userToken': session.userToken,
      'loginType': '2',
      ...WiwyConfig.device(sn: identity.sn),
    };

    final data = await _post('/api/portalCore/v6/getLiveData', payload);
    final list = (data['channelList'] as List?) ?? const [];
    final channels = <WiwyChannelData>[];
    for (final item in list) {
      if (item is! Map) continue;
      final channel = WiwyChannelData.fromJson(item.cast<String, dynamic>());
      if (channel != null) channels.add(channel);
    }

    // El portal responde 304 cuando el cuerpo incluye dataVersion; al no
    // enviarlo, la respuesta siempre trae la lista completa.
    if (channels.isEmpty && data.isEmpty) {
      throw WiwyException('empty', 'la columna $columnId no devolvió canales');
    }
    return channels;
  }
}
