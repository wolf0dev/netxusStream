/// Fuente de canales de WiwyXuper con refresco automático.
///
/// Mantiene el `userToken` y los `Content-Auth` al día sin intervención del
/// usuario:
///
///  * cachea en disco la lista + credenciales (arranque instantáneo),
///  * refresca cuando el `Content-Auth` está por caducar (o al abrir la app),
///  * conserva la misma URL por canal para no romper favoritos,
///  * actualiza las cabeceras *en sitio*, así un canal ya abierto sigue
///    recibiendo credenciales nuevas,
///  * reintenta con el CDN alternativo si el principal deja de listar el canal.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/channel.dart';
import 'wiwy_identity.dart';
import 'wiwy_portal.dart';
import 'wiwy_vod.dart';

/// Almacenamiento simple (archivo o memoria) para la caché.
abstract class WiwyStore {
  Future<String?> read(String name);
  Future<void> write(String name, String contents);
}

/// Implementación con `dart:io`: vale para Android, Windows, macOS y Linux.
class FileWiwyStore implements WiwyStore {
  FileWiwyStore(this.directory);

  final String directory;

  File _file(String name) => File('$directory${Platform.pathSeparator}$name');

  @override
  Future<String?> read(String name) async {
    try {
      final file = _file(name);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String name, String contents) async {
    try {
      final file = _file(name);
      await file.parent.create(recursive: true);
      await file.writeAsString(contents, flush: true);
    } catch (_) {
      // La caché nunca debe romper la reproducción.
    }
  }
}

/// Caché en memoria (tests y CLI).
class MemoryWiwyStore implements WiwyStore {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String name) async => _data[name];

  @override
  Future<void> write(String name, String contents) async {
    _data[name] = contents;
  }
}

/// Lista ya lista para la interfaz.
class WiwyPlaylist {
  const WiwyPlaylist({
    required this.channels,
    required this.fetchedAt,
    this.authExpiresAt,
    this.licenseExpiresAt,
  });

  final List<Channel> channels;
  final DateTime fetchedAt;
  final DateTime? authExpiresAt;
  final DateTime? licenseExpiresAt;

  bool get isEmpty => channels.isEmpty;
}

/// Proveedor de canales con refresco automático.
class WiwySource {
  WiwySource({
    WiwyPortal? portal,
    WiwyStore? store,
    List<int>? columns,
    this.earlyRefresh = const Duration(minutes: 20),
    this.forceCooldown = const Duration(minutes: 2),
    this.logger,
  }) : _portal = portal ?? WiwyPortal(),
       _store = store ?? MemoryWiwyStore(),
       _columns = columns ?? WiwyConfig.columns;

  static const String _cacheName = 'wiwy_cache_v1.json';
  static const String _m3uName = 'wiwy.m3u';

  final WiwyPortal _portal;
  final WiwyStore _store;
  final List<int> _columns;
  final Duration earlyRefresh;

  /// Cliente HTTP del portal (el catálogo VOD lo usa con la sesión activa).
  WiwyPortal get portal => _portal;

  /// Frecuencia mínima entre dos renovaciones forzadas seguidas.
  final Duration forceCooldown;
  final void Function(String message)? logger;

  /// Se llama cada vez que un refresco automático termina con datos nuevos.
  void Function(WiwyPlaylist playlist)? onUpdated;

  final Map<String, Map<String, String>> _headerMaps = {};
  final Map<String, String> _licenses = {};
  WiwyPlaylist? _current;
  WiwySession? _session;
  WiwySlbInfo? _slb;
  late final WiwyVodService vod = WiwyVodService(this);
  Timer? _timer;
  int _openNum = 0;
  DateTime? _lastRefreshAt;
  bool _refreshing = false;
  Future<WiwyPlaylist>? _inFlight;

  /// Identidad de esta instalación (se resuelve una sola vez por proceso).
  WiwyIdentity? _identity;
  Future<WiwyIdentity>? _identityInFlight;

  /// Identidad efectiva: la registrada o, si aún no hay, la histórica.
  WiwyIdentity get identity => _identity ?? WiwyIdentity.legacy;

  WiwyPlaylist? get current => _current;
  DateTime? get authExpiresAt => _current?.authExpiresAt;
  bool get isRefreshing => _refreshing;

  /// Sesión del portal en uso (para el catálogo VOD).
  WiwySession? get session => _session;

  /// Última información de CDN recibida (directo y VOD).
  WiwySlbInfo? get slb => _slb;

  /// Devuelve una sesión válida, activando el portal si hace falta.
  Future<WiwySession> ensureSession() async {
    final current = _session;
    if (current != null && current.isValid) return current;
    await load();
    final session = _session;
    if (session == null || !session.isValid) {
      throw WiwyException('active', 'el portal no entregó credenciales');
    }
    return session;
  }

  /// Resuelve la identidad de esta instalación antes de activar el portal.
  ///
  /// * Si ya se registró una vez, la lee del disco (arranque sin red).
  /// * Si no existe, registra un dispositivo nuevo con el flujo móvil y la
  ///   guarda; así cada instalación tiene su propia cuenta y dos equipos pueden
  ///   reproducir a la vez sin `aaa100083`.
  /// * Si el registro falla (sin red, portal caído), usa la identidad histórica
  ///   y no la persiste: se reintenta en el siguiente arranque.
  Future<WiwyIdentity> _ensureIdentity() {
    final cached = _identity;
    if (cached != null) return Future.value(cached);
    final running = _identityInFlight;
    if (running != null) return running;
    final future = _resolveIdentity();
    _identityInFlight = future;
    return future.whenComplete(() => _identityInFlight = null);
  }

  Future<WiwyIdentity> _resolveIdentity() async {
    final stored = await _store.read(WiwyIdentity.storageName);
    final parsed = stored == null || stored.isEmpty
        ? null
        : WiwyIdentity.tryParse(stored);
    if (parsed != null) {
      _applyIdentity(parsed);
      _log('identidad guardada: sn=${parsed.sn}');
      return parsed;
    }

    try {
      final registry = WiwyIdentityRegistry(
        client: _portal.client,
        logger: _log,
      );
      final fresh = await registry.register();
      await _store.write(WiwyIdentity.storageName, fresh.encode());
      _applyIdentity(fresh);
      _log('identidad registrada: sn=${fresh.sn} userId=${fresh.userId}');
      return fresh;
    } catch (error) {
      _log('registro de identidad falló ($error); usando la histórica');
      final legacy = WiwyIdentity.legacy;
      _applyIdentity(legacy);
      return legacy;
    }
  }

  void _applyIdentity(WiwyIdentity identity) {
    final previous = _identity;
    if (previous != null && previous.sn != identity.sn) {
      // Identidad distinta: la lista, la sesión y las licencias en memoria
      // pertenecen a la anterior y no deben reutilizarse.
      _current = null;
      _session = null;
      _slb = null;
      _headerMaps.clear();
      _licenses.clear();
    }
    _identity = identity;
    // `WiwyPortal` lee `identity` en cada petición: se asigna una sola vez.
    _portal.identity = identity;
  }

  /// Códigos del portal que indican una sesión muerta (`userToken` inválido).
  ///
  /// `aaa100083` es "la cuenta ya inició sesión en otro dispositivo": el portal
  /// solo mantiene una sesión por cuenta y cada `v8/active` invalida la
  /// anterior (también la de otra instalación de la app en otro equipo).
  static const Set<String> _sessionInvalidCodes = {'aaa100083'};

  /// Renovación ligera de sesión: activa y pide los CDN, sin recargar las
  /// ~1000 columnas de canales. Se usa como auto-reparación cuando el portal
  /// rechaza el `userToken` vigente. Si ya hay una renovación en curso, se
  /// reutiliza (dos llamadas concurrentes no deben activar dos veces).
  Future<WiwySession> renewSession() {
    final refresh = _inFlight;
    if (refresh != null) {
      // Ya hay un refresco completo en curso (también activa una sesión):
      // espera su resultado en lugar de activar otra en paralelo.
      return refresh.then((_) => ensureSession());
    }
    final running = _renewInFlight;
    if (running != null) return running;
    final future = _renewSessionInternal();
    _renewInFlight = future;
    return future.whenComplete(() => _renewInFlight = null);
  }

  Future<WiwySession>? _renewInFlight;

  Future<WiwySession> _renewSessionInternal() async {
    await _ensureIdentity();
    _openNum = _openNum <= 0 ? 600 : _openNum + 1;
    final session = await _portal.activate(openNum: _openNum);
    if (!session.isValid) {
      throw WiwyException('active', 'la activación no devolvió userToken');
    }
    // Asigna la sesión ANTES de pedir los CDN: si `getSlbInfo` falla, el token
    // anterior ya está muerto y conservarlo provocaría `aaa100083` en bucle.
    _session = session;
    _lastRefreshAt = DateTime.now();

    try {
      final info = await _portal.getSlbInfo(session);
      _slb = info;
      // Los CDN nuevos llegan con `Content-Auth` fresco: actualiza las
      // cabeceras de los canales abiertos sin recargar la lista.
      final authByHost = {for (final cdn in info.cdns) cdn.host: cdn.auth};
      final current = _current;
      if (current != null && authByHost.isNotEmpty) {
        for (final channel in current.channels) {
          final host = Uri.tryParse(channel.url)?.host;
          final auth = host == null ? null : authByHost[host];
          if (auth == null || auth.isEmpty) continue;
          final map = _headerMaps[channel.tvgId];
          if (map == null) continue;
          map['Content-Auth'] = auth;
        }
        await _persist(current, session, info.cdns, authByHost);
      }
    } catch (error) {
      // Los CDN viejos siguen vigentes ~6 h: con la sesión nueva basta para el
      // catálogo y la reproducción.
      _log('getSlbInfo tras renovar sesión falló: $error');
    }
    return session;
  }

  /// Ejecuta [action] con una sesión que se auto-repara.
  ///
  /// Si el portal responde que el `userToken` ya no es válido (otra
  /// activación lo invalidó), renueva la sesión y reintenta una vez. Así el
  /// catálogo se recupera solo cuando otra instalación de la app (Android,
  /// Windows) re-activa la misma cuenta.
  Future<T> withSession<T>(
    Future<T> Function(WiwySession session) action,
  ) async {
    var session = await ensureSession();
    try {
      return await action(session);
    } on WiwyException catch (error) {
      if (!_sessionInvalidCodes.contains(error.code)) rethrow;
      _log('sesión rechazada (${error.code}); renovando y reintentando');
      final fresh = await renewSession();
      return action(fresh);
    }
  }

  /// `getSlbInfo` con auto-reparación: si otra instalación activó la cuenta
  /// justo después de nuestra activación, el token recién creado también
  /// puede morir antes de pedir los CDN.
  Future<WiwySlbInfo> _slbWithRetry(WiwySession session) async {
    try {
      return await _portal.getSlbInfo(session);
    } on WiwyException catch (error) {
      if (!_sessionInvalidCodes.contains(error.code)) rethrow;
      _log('CDN rechazados (${error.code}); renovando y reintentando');
      final fresh = await renewSession();
      return _portal.getSlbInfo(fresh);
    }
  }

  void _log(String message) => logger?.call(message);

  // ------------------------------------------------------------------ carga

  /// Devuelve la lista utilizable. Usa caché si sigue vigente; si no, refresca.
  Future<WiwyPlaylist> load({bool force = false}) async {
    await _ensureIdentity();
    if (!force) {
      final cached = _current ?? await _readCache();
      if (cached != null && _isFresh(cached)) {
        _current = cached;
        _lastRefreshAt = cached.fetchedAt;
        _scheduleNextRefresh();
        return cached;
      }
    }

    try {
      final fresh = await refresh();
      return fresh;
    } catch (error) {
      _log('refresco fallido: $error');
      final fallback = _current ?? await _readCache();
      if (fallback != null) {
        _current = fallback;
        _lastRefreshAt = fallback.fetchedAt;
        _scheduleNextRefresh();
        return fallback;
      }
      rethrow;
    }
  }

  /// Fuerza una descarga nueva. Si ya hay una en curso, la reutiliza.
  Future<WiwyPlaylist> refresh() {
    final running = _inFlight;
    if (running != null) return running;
    final future = _refreshInternal();
    _inFlight = future;
    return future.whenComplete(() => _inFlight = null);
  }

  Future<WiwyPlaylist> _refreshInternal() async {
    _refreshing = true;
    try {
      await _ensureIdentity();
      _openNum = _openNum <= 0 ? 600 : _openNum + 1;
      final session = await _portal.activate(openNum: _openNum);
      if (!session.isValid) {
        throw WiwyException('active', 'la activación no devolvió userToken');
      }
      // Se guarda la sesión ANTES de pedir los CDN: cada `v8/active` invalida
      // el `userToken` anterior, y si `getSlbInfo` falla a continuación habría
      // que seguir usando un token muerto (el portal responde aaa100083).
      _session = session;
      _log('activado userId=${session.userId}');

      var info = await _slbWithRetry(session);
      _slb = info;
      var cdns = info.liveCdns;
      if (cdns.isEmpty) throw WiwyException('slb', 'sin CDN de directo');
      _log('CDN: ${cdns.map((c) => '${c.host}#${c.type}').join(', ')}');

      var byType = <int, List<WiwyCdn>>{};
      for (final cdn in cdns) {
        byType.putIfAbsent(cdn.type, () => []).add(cdn);
      }
      var authByHost = {for (final cdn in info.cdns) cdn.host: cdn.auth};

      final channels = <Channel>[];
      final seen = <String>{};

      // 1) Descarga todas las columnas antes de construir los canales: el
      // ranking de CDN necesita un canal de muestra por tipo.
      final allData = <WiwyChannelData>[];
      for (final column in _columns) {
        List<WiwyChannelData> data;
        try {
          // `withSession`: si otra instalación activó la cuenta entre columnas,
          // el token muere y el portal responde aaa100083. Renueva y reintenta
          // en lugar de devolver la lista incompleta.
          data = await withSession((s) => _portal.getLiveData(column, s));
        } catch (error) {
          _log('columna $column falló: $error');
          continue;
        }
        _log('columna $column: ${data.length} canales');
        allData.addAll(data);
      }

      // Si la sesión se renovó durante la descarga, `_slb` trae hosts y
      // `Content-Auth` nuevos: reconstruye las estructuras con ellos.
      if (!identical(_slb, info)) {
        info = _slb ?? info;
        cdns = info.liveCdns;
        byType = <int, List<WiwyCdn>>{};
        for (final cdn in cdns) {
          byType.putIfAbsent(cdn.type, () => []).add(cdn);
        }
        authByHost = {for (final cdn in info.cdns) cdn.host: cdn.auth};
      }

      // 2) Ordena los hosts de cada tipo por rendimiento sostenido: algunos
      // CDN responden bien a un sondeo corto y luego estrangulan la conexión
      // larga (bucle de buffering en el reproductor).
      final ranked = <int, List<WiwyCdn>>{};
      for (final entry in byType.entries) {
        // Canal de muestra del mismo tipo (los playCode no siempre funcionan
        // en hosts de otro tipo); si no hay, cualquier canal con playCode.
        WiwyChannelData? sample;
        for (final channel in allData) {
          if (channel.cdnType == entry.key && channel.playCode.isNotEmpty) {
            sample = channel;
            break;
          }
        }
        sample ??= allData
            .where((channel) => channel.playCode.isNotEmpty)
            .firstOrNull;
        ranked[entry.key] = sample == null
            ? entry.value
            : await _rankCdns(entry.value, sample);
      }

      // 3) Construye los canales con el host más rápido primero.
      for (final channel in allData) {
        final key = channel.channelCode.isEmpty
            ? channel.playCode
            : channel.channelCode;
        if (!seen.add(key)) continue;

        final candidates = <WiwyCdn>[
          ...?ranked[channel.cdnType],
          ...?ranked[4],
          ...?ranked[1],
        ];
        if (candidates.isEmpty) continue;
        final cdn = candidates.first;

        final url = 'http://${cdn.host}/live/${channel.playCode}.m3u8';
        final headers = _headersFor(cdn, channel.license);
        // Se reutiliza el mapa del canal para que los `Channel` ya abiertos
        // reciban las credenciales nuevas sin cambiar de URL.
        final target = _headerMaps.putIfAbsent(key, () => <String, String>{});
        target
          ..clear()
          ..addAll(headers);
        _licenses[key] = channel.license;

        channels.add(
          Channel(
            name: channel.name,
            url: url,
            logo: channel.logo,
            group: 'Servidor',
            tvgId: key,
            headerResolver: () => _headerMaps[key] ?? const {},
          ),
        );
      }

      if (channels.isEmpty) {
        throw WiwyException('empty', 'el portal no devolvió canales');
      }

      DateTime? licenseExpiry;
      for (final license in _licenses.values) {
        final exp = _expiryOf(license);
        if (exp == null) continue;
        if (licenseExpiry == null || exp.isBefore(licenseExpiry)) {
          licenseExpiry = exp;
        }
      }

      final playlist = WiwyPlaylist(
        channels: List<Channel>.unmodifiable(channels),
        fetchedAt: DateTime.now(),
        authExpiresAt: info.expiresAt,
        licenseExpiresAt: licenseExpiry,
      );

      _current = playlist;
      _lastRefreshAt = DateTime.now();
      await _persist(playlist, session, info.cdns, authByHost);
      _scheduleNextRefresh();
      _log('lista lista: ${channels.length} canales');
      return playlist;
    } finally {
      _refreshing = false;
    }
  }

  Map<String, String> _headersFor(WiwyCdn cdn, String license) => {
    'User-Agent': WiwyConfig.playerUserAgent,
    'App': WiwyConfig.playerApp,
    'App-Version': WiwyConfig.playerAppVersion,
    'Content-Auth': cdn.auth,
    'Content-License': license,
    'Pragma': WiwyConfig.playerPragma,
    'X-Buffer': WiwyConfig.playerBuffer,
  };

  /// Ordena los hosts de un tipo de CDN por rendimiento sostenido.
  ///
  /// Para cada host descarga el manifiesto del canal de muestra y su primer
  /// segmento, midiendo el tramo final de la descarga (~2 s en total por host,
  /// en paralelo). Los hosts que no sirven el manifiesto quedan al final.
  /// Con un solo host no hay nada que ordenar.
  Future<List<WiwyCdn>> _rankCdns(
    List<WiwyCdn> cdns,
    WiwyChannelData sample,
  ) async {
    if (cdns.length < 2 || sample.playCode.isEmpty) return cdns;

    final scores = await Future.wait([
      for (final cdn in cdns) _measureLive(cdn, sample),
    ]);
    final ranked = <_LiveScore>[];
    final failed = <WiwyCdn>[];
    for (var i = 0; i < cdns.length; i++) {
      final score = scores[i];
      if (score == null) {
        failed.add(cdns[i]);
      } else {
        ranked.add(score);
      }
    }
    ranked.sort((a, b) => b.kbps.compareTo(a.kbps));
    final order = [for (final score in ranked) score.cdn, ...failed];
    if (order.length != cdns.length) return cdns;
    _log(
      'CDN ${cdns.first.type}: ${[for (final score in ranked) '${score.cdn.host}=${score.kbps.round()}kbps'].join(', ')}',
    );
    return order;
  }

  /// Mide manifiesto + primer segmento de un host live.
  Future<_LiveScore?> _measureLive(WiwyCdn cdn, WiwyChannelData sample) async {
    final client = http.Client();
    try {
      final url = 'http://${cdn.host}/live/${sample.playCode}.m3u8';
      final response = await client
          .get(Uri.parse(url), headers: _headersFor(cdn, sample.license))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final text = utf8.decode(response.bodyBytes, allowMalformed: true);
      final segments = text
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty && !line.startsWith('#'))
          .toList();
      if (segments.isEmpty) return null;
      final base = Uri.parse(url);
      final segmentUrl = segments.first.startsWith('http')
          ? segments.first
          : base.resolve(segments.first).toString();

      final request = http.Request('GET', Uri.parse(segmentUrl))
        ..headers.addAll(_headersFor(cdn, sample.license));
      final stream = await client
          .send(request)
          .timeout(const Duration(seconds: 8));

      final sw = Stopwatch()..start();
      var bytes = 0;
      var tailBytes = 0;
      var tailMs = 0;
      var windowOpened = false;
      await for (final chunk in stream.stream) {
        bytes += chunk.length;
        final ms = sw.elapsedMilliseconds;
        if (!windowOpened && ms >= 500) {
          windowOpened = true;
          tailBytes = 0;
          tailMs = 0;
        }
        if (windowOpened) {
          tailBytes += chunk.length;
          tailMs = ms - 500;
        }
        if (ms >= 2000 || bytes >= 4 * 1024 * 1024) break;
      }
      if (!windowOpened || tailBytes <= 0 || tailMs <= 0) {
        if (bytes <= 0) return null;
        return _LiveScore(cdn, bytes * 8 / 1000 / sw.elapsedMilliseconds);
      }
      return _LiveScore(cdn, tailBytes * 8 / 1000 / tailMs);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static DateTime? _expiryOf(String params) {
    for (final part in params.split('&')) {
      if (part.startsWith('expired=')) {
        final value = int.tryParse(part.substring('expired='.length));
        if (value != null) {
          return DateTime.fromMillisecondsSinceEpoch(value * 1000);
        }
      }
    }
    return null;
  }

  bool _isFresh(WiwyPlaylist playlist) {
    final now = DateTime.now();
    final auth = playlist.authExpiresAt;
    final license = playlist.licenseExpiresAt;
    if (auth == null) return false;
    if (now.isAfter(auth.subtract(earlyRefresh))) return false;
    if (license != null && now.isAfter(license)) return false;
    return true;
  }

  // ------------------------------------------------------- refresco periódico

  void _scheduleNextRefresh() {
    _timer?.cancel();
    final auth = _current?.authExpiresAt;
    if (auth == null) return;
    var delay = auth.difference(DateTime.now()) - earlyRefresh;
    if (delay < const Duration(minutes: 1)) {
      delay = const Duration(minutes: 1);
    }
    _timer = Timer(delay, () async {
      try {
        final playlist = await refresh();
        onUpdated?.call(playlist);
      } catch (error) {
        _log('refresco automático fallido: $error');
        // Reintenta en 10 minutos.
        _timer = Timer(const Duration(minutes: 10), _scheduleNextRefresh);
      }
    });
    _log('próximo refresco en ${delay.inMinutes} min');
  }

  /// Refresca si las credenciales están por caducar (usar al abrir un canal).
  ///
  /// Con [force] se renueva aunque la caducidad parezca lejana: el CDN puede
  /// invalidar un `Content-Auth` antes de tiempo y entonces la reproducción
  /// falla. Se limita a una renovación forzada cada [forceCooldown] para no
  /// castigar la red en cada reintento de un corte de señal.
  Future<void> ensureFresh({bool force = false}) async {
    final playlist = _current;
    if (playlist != null && _isFresh(playlist)) {
      final now = DateTime.now();
      final last = _lastRefreshAt;
      if (!force || (last != null && now.difference(last) < forceCooldown)) {
        return;
      }
    }
    try {
      await (force ? refresh() : load());
    } catch (_) {
      // Si falla, se reproduce con lo que haya.
    }
  }

  // -------------------------------------------------------------- persistencia

  Future<void> _persist(
    WiwyPlaylist playlist,
    WiwySession session,
    List<WiwyCdn> cdns,
    Map<String, String> authByHost,
  ) async {
    try {
      final data = <String, dynamic>{
        'version': 2,
        'fetchedAt': playlist.fetchedAt.millisecondsSinceEpoch,
        'openNum': _openNum,
        'sn': identity.sn,
        'session': session.toJson(),
        'cdns': cdns.map((c) => c.toJson()).toList(),
        'auths': authByHost,
        'channels': [
          for (final channel in playlist.channels)
            {
              'name': channel.name,
              'url': channel.url,
              'code': channel.tvgId,
              'logo': channel.logo,
              'group': channel.group,
              'license': _licenses[channel.tvgId] ?? '',
            },
        ],
      };
      await _store.write(_cacheName, jsonEncode(data));
      await _store.write(_m3uName, buildM3u(playlist));
    } catch (error) {
      _log('no se pudo guardar la caché: $error');
    }
  }

  Future<WiwyPlaylist?> _readCache() async {
    final raw = await _store.read(_cacheName);
    if (raw == null || raw.isEmpty) return null;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      // La versión 1 solo guardaba los CDN de directo; sin los de VOD el
      // catálogo no puede resolver la reproducción. Se fuerza un refresco.
      if ((int.tryParse('${data['version']}') ?? 1) < 2) return null;

      // La caché pertenece a una identidad concreta: si el `sn` no coincide
      // (instalación registrada nueva, o caché anterior sin `sn`), se descarta
      // para no mezclar sesiones ni provocar `aaa100083`.
      final cachedSn = '${data['sn'] ?? ''}'.trim();
      if (cachedSn.isEmpty) {
        if (!identity.isLegacy) return null;
      } else if (cachedSn != identity.sn) {
        return null;
      }

      final cdns = <WiwyCdn>[
        for (final item in (data['cdns'] as List?) ?? const [])
          if (item is Map) WiwyCdn.fromJson(item.cast<String, dynamic>()),
      ];
      final storedAuths = data['auths'];
      final authByHost = <String, String>{
        if (storedAuths is Map)
          for (final entry in storedAuths.entries)
            '${entry.key}': '${entry.value}',
      };
      if (cdns.isEmpty) return null;
      for (final cdn in cdns) {
        final auth = authByHost[cdn.host];
        if (auth != null && auth.isNotEmpty) {
          // Conserva el Content-Auth guardado (WiWY sostiene el mismo objeto).
          final index = cdns.indexOf(cdn);
          cdns[index] = WiwyCdn(
            type: cdn.type,
            host: cdn.host,
            auth: auth,
            tag: cdn.tag,
          );
        }
      }

      // Restaura la sesión y los CDN para el catálogo VOD sin activar de nuevo.
      final storedSession = data['session'];
      if (storedSession is Map) {
        _session = WiwySession.fromJson(storedSession.cast<String, dynamic>());
      }
      _slb = WiwySlbInfo(cdns: List<WiwyCdn>.unmodifiable(cdns), raw: const {});

      final byHost = {for (final cdn in cdns) cdn.host: cdn};
      final preferred = cdns.where((c) => c.tag == 'live' && c.type == 4);
      final fallback = preferred.isEmpty
          ? cdns.where((c) => c.tag == 'live')
          : preferred;

      final channels = <Channel>[];
      final licenses = <String, String>{};
      for (final item in (data['channels'] as List?) ?? const []) {
        if (item is! Map) continue;
        final url = '${item['url'] ?? ''}';
        final code = '${item['code'] ?? ''}';
        final license = '${item['license'] ?? ''}';
        if (url.isEmpty || code.isEmpty) continue;

        final host = Uri.tryParse(url)?.host ?? '';
        final cdn = byHost[host] ?? (fallback.isEmpty ? null : fallback.first);
        if (cdn == null) continue;

        final headers = _headersFor(cdn, license);
        _headerMaps[code] = headers;
        licenses[code] = license;

        channels.add(
          Channel(
            name: '${item['name'] ?? code}',
            url: url,
            logo: '${item['logo'] ?? ''}',
            group: '${item['group'] ?? 'Servidor'}',
            tvgId: code,
            headerResolver: () => _headerMaps[code] ?? const {},
          ),
        );
      }
      if (channels.isEmpty) return null;

      _openNum = int.tryParse('${data['openNum'] ?? ''}') ?? _openNum;
      _licenses.addAll(licenses);

      DateTime? licenseExpiry;
      for (final license in licenses.values) {
        final exp = _expiryOf(license);
        if (exp == null) continue;
        if (licenseExpiry == null || exp.isBefore(licenseExpiry)) {
          licenseExpiry = exp;
        }
      }

      final fetchedAt = DateTime.fromMillisecondsSinceEpoch(
        int.tryParse('${data['fetchedAt'] ?? ''}') ?? 0,
      );

      return WiwyPlaylist(
        channels: List<Channel>.unmodifiable(channels),
        fetchedAt: fetchedAt,
        authExpiresAt: cdns
            .where((c) => c.tag == 'live')
            .map((c) => c.expiresAt)
            .whereType<DateTime>()
            .fold<DateTime?>(
              null,
              (a, b) => a == null || b.isBefore(a) ? b : a,
            ),
        licenseExpiresAt: licenseExpiry,
      );
    } catch (error) {
      _log('caché ilegible: $error');
      return null;
    }
  }

  // ------------------------------------------------------------------- m3u

  /// Exporta la lista actual en formato VLC/Kodi (con cabeceras por canal).
  String buildM3u([WiwyPlaylist? playlist]) {
    final target = playlist ?? _current;
    final buffer = StringBuffer('#EXTM3U\n');
    if (target == null) return buffer.toString();

    for (final channel in target.channels) {
      final headers = channel.httpHeaders;
      buffer.write(
        '#EXTINF:-1 tvg-id="${channel.tvgId}" '
        'tvg-logo="${channel.logo}" group-title="${channel.group}",'
        '${channel.name}\n',
      );
      for (final entry in headers.entries) {
        buffer.write('#EXTVLCOPT:http-header=${entry.key}: ${entry.value}\n');
      }
      buffer.writeln(channel.url);
      buffer.writeln();
    }
    return buffer.toString();
  }

  /// Recrea los clientes HTTP para aplicar un cambio de VPN/proxy.
  void refreshNetwork() => _portal.resetClient();

  void dispose() {
    _timer?.cancel();
    _portal.close();
  }
}

/// Rendimiento medido de un host live durante el ranking.
class _LiveScore {
  _LiveScore(this.cdn, this.kbps);

  final WiwyCdn cdn;

  /// Kilobits por segundo sostenidos tras la ráfaga inicial.
  final double kbps;
}
