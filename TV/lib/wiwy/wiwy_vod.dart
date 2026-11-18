/// Catálogo de películas y series de WiwyXuper en Dart puro.
///
/// Todo el flujo sale del propio portal, sin emulador ni APK:
///
/// ```text
/// v3/getShelveData  -> lista de una columna (películas, series, infantil)
/// v4/getItemData    -> ficha con sinopsis, reparto y capítulos
/// v10/startPlayVOD  -> media_code + licencia del CDN
/// ```
///
/// La resolución de la URL final del CDN la hace el SDK nativo del APK, así
/// que aquí se reconstruye con las mismas piezas que usa el directo
/// (`/vod/<media_code>.<ext>` + `Content-Auth` + `Content-License`).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/channel.dart';
import '../services/proxy_service.dart';
import 'wiwy_portal.dart';
import 'wiwy_source.dart';

/// Tipo de contenido de una estantería.
enum WiwyVodKind {
  movies(87027, 'Películas', 'movie'),
  series(87028, 'Series', 'teleplay'),
  kids(87029, 'Infantil', 'kids');

  const WiwyVodKind(this.columnId, this.label, this.programType);

  final int columnId;
  final String label;
  final String programType;
}

/// Un título del catálogo (lo que muestra la cuadrícula).
class WiwyVodAsset {
  const WiwyVodAsset({
    required this.contentId,
    required this.name,
    required this.type,
    required this.programType,
    required this.poster,
    required this.backdrop,
    required this.score,
    required this.year,
    required this.duration,
    required this.tags,
    required this.synopsis,
    required this.episodeCount,
  });

  final String contentId;
  final String name;

  /// `1` película, `0` serie.
  final String type;
  final String programType;
  final String poster;
  final String backdrop;
  final double score;
  final String year;
  final String duration;
  final String tags;
  final String synopsis;
  final int episodeCount;

  bool get isSeries => type == '0' || programType == 'teleplay';

  /// Copia compacta para «Continuar viendo» (SharedPreferences).
  Map<String, dynamic> toResumeJson() => {
    'contentId': contentId,
    'name': name,
    'type': type,
    'programType': programType,
    'poster': poster,
    'backdrop': backdrop,
    'score': score,
    'year': year,
    'duration': duration,
    'tags': tags,
    'synopsis': synopsis,
    'episodeCount': episodeCount,
  };

  static WiwyVodAsset? fromResumeJson(Map<String, dynamic> json) {
    final contentId = '${json['contentId'] ?? ''}'.trim();
    final name = '${json['name'] ?? ''}'.trim();
    if (contentId.isEmpty || name.isEmpty) return null;
    return WiwyVodAsset(
      contentId: contentId,
      name: name,
      type: '${json['type'] ?? ''}',
      programType: '${json['programType'] ?? ''}',
      poster: '${json['poster'] ?? ''}',
      backdrop: '${json['backdrop'] ?? ''}',
      score: (json['score'] as num?)?.toDouble() ?? 0,
      year: '${json['year'] ?? ''}',
      duration: '${json['duration'] ?? ''}',
      tags: '${json['tags'] ?? ''}',
      synopsis: '${json['synopsis'] ?? ''}',
      episodeCount: (json['episodeCount'] as num?)?.toInt() ?? 0,
    );
  }

  static WiwyVodAsset? fromJson(Map<String, dynamic> json) {
    final contentId = '${json['contentId'] ?? ''}'.trim();
    final name = '${json['name'] ?? json['alias'] ?? ''}'.trim();
    if (contentId.isEmpty || name.isEmpty) return null;

    var poster = '';
    var backdrop = '';
    var wide = '';
    for (final item in (json['posterList'] as List?) ?? const []) {
      if (item is! Map) continue;
      final url = '${item['fileUrl'] ?? ''}'.trim();
      if (url.isEmpty) continue;
      switch ('${item['fileType'] ?? ''}') {
        case 'icon':
          poster = url;
        case 'stage':
          backdrop = url;
        case 'poster':
          wide = url;
      }
    }

    return WiwyVodAsset(
      contentId: contentId,
      name: name,
      type: '${json['type'] ?? ''}',
      programType: '${json['programType'] ?? ''}',
      poster: poster.isNotEmpty ? poster : wide,
      backdrop: backdrop.isNotEmpty ? backdrop : wide,
      score: double.tryParse('${json['score'] ?? ''}') ?? 0,
      year: '${json['releaseTime'] ?? ''}'.split('-').first,
      duration: '${json['duration'] ?? ''}',
      tags: '${json['tags'] ?? ''}'.replaceAll(',', ' · '),
      synopsis: '${json['description'] ?? ''}'.trim(),
      episodeCount: int.tryParse('${json['volumnCount'] ?? ''}') ?? 0,
    );
  }
}

/// Capítulo de una serie.
class WiwyVodEpisode {
  const WiwyVodEpisode({
    required this.contentId,
    required this.name,
    required this.number,
    required this.duration,
  });

  final String contentId;
  final String name;
  final int number;
  final String duration;

  /// Copia compacta para «Continuar viendo» (SharedPreferences).
  Map<String, dynamic> toResumeJson() => {
    'contentId': contentId,
    'name': name,
    'number': number,
    'duration': duration,
  };

  static WiwyVodEpisode? fromResumeJson(Map<String, dynamic> json) {
    final contentId = '${json['contentId'] ?? ''}'.trim();
    if (contentId.isEmpty) return null;
    return WiwyVodEpisode(
      contentId: contentId,
      name: '${json['name'] ?? ''}'.trim(),
      number: (json['number'] as num?)?.toInt() ?? 0,
      duration: '${json['duration'] ?? ''}',
    );
  }

  static WiwyVodEpisode? fromJson(Map<String, dynamic> json) {
    final contentId = '${json['contentId'] ?? ''}'.trim();
    if (contentId.isEmpty) return null;
    return WiwyVodEpisode(
      contentId: contentId,
      name: '${json['name'] ?? ''}'.trim(),
      number: int.tryParse('${json['seriesNumber'] ?? ''}') ?? 0,
      duration: '${json['duration'] ?? ''}',
    );
  }
}

/// Temporada de una serie.
class WiwyVodSeason {
  const WiwyVodSeason({required this.contentId, required this.number});

  final String contentId;
  final int number;
}

/// Ficha completa de un título.
class WiwyVodDetail {
  const WiwyVodDetail({
    required this.asset,
    required this.synopsis,
    required this.actors,
    required this.director,
    required this.year,
    required this.audio,
    required this.episodes,
    required this.seasons,
  });

  final WiwyVodAsset asset;
  final String synopsis;
  final String actors;
  final String director;
  final String year;
  final String audio;
  final List<WiwyVodEpisode> episodes;
  final List<WiwyVodSeason> seasons;

  bool get hasEpisodes => episodes.isNotEmpty;
}

/// Media lista para reproducir: `media_code` + licencia + cabeceras.
class WiwyVodPlayback {
  const WiwyVodPlayback({
    required this.mediaCode,
    required this.originalId,
    required this.license,
    required this.quality,
    required this.encodeFormat,
    required this.videoFormat,
    required this.title,
    required this.episodeTitle,
  });

  final String mediaCode;
  final String originalId;
  final String license;
  final String quality;
  final String encodeFormat;
  final String videoFormat;
  final String title;
  final String episodeTitle;

  static WiwyVodPlayback? fromJson(
    Map<String, dynamic> json, {
    required String title,
    required String episodeTitle,
  }) {
    Map? best;
    for (final episode in (json['episodeList'] as List?) ?? const []) {
      if (episode is! Map) continue;
      for (final total in (episode['totalMovieList'] as List?) ?? const []) {
        if (total is! Map) continue;
        for (final movie in (total['movieList'] as List?) ?? const []) {
          if (movie is! Map) continue;
          final code = '${movie['contentId'] ?? ''}'.trim();
          if (code.isEmpty) continue;
          best ??= movie;
          // Preferimos 720p para que arranque rápido y no sature la red.
          if ('${movie['quality'] ?? ''}'.startsWith('720')) best = movie;
        }
      }
    }
    if (best == null) return null;

    var license = '';
    for (final item in (best['licenseList'] as List?) ?? const []) {
      if (item is! Map) continue;
      final value = '${item['license'] ?? ''}'.trim();
      if (value.isEmpty) continue;
      if ('${item['tag'] ?? ''}' == 'free' || license.isEmpty) license = value;
    }

    return WiwyVodPlayback(
      mediaCode: '${best['contentId'] ?? ''}'.trim(),
      originalId: '${best['originalContentId'] ?? ''}'.trim(),
      license: license,
      quality: '${best['quality'] ?? ''}',
      encodeFormat: '${best['encodeFormat'] ?? ''}',
      videoFormat: '${best['videoFormat'] ?? ''}',
      title: title,
      episodeTitle: episodeTitle,
    );
  }
}

/// Página de resultados de la búsqueda global del portal.
class WiwyVodSearchPage {
  const WiwyVodSearchPage({required this.assets, required this.total});

  final List<WiwyVodAsset> assets;

  /// Total de coincidencias en el portal (puede superar a [assets]).
  final int total;
}

/// Servicio de catálogo VOD sobre un [WiwySource] ya autenticado.
///
/// Todas las llamadas pasan por `WiwySource.withSession`: si el portal
/// rechaza el `userToken` porque otra activación lo invalidó (otra
/// instalación de la app, otro dispositivo), se renueva la sesión y se
/// reintenta automáticamente en lugar de mostrar `aaa100083` al usuario.
class WiwyVodService {
  WiwyVodService(this._source);

  final WiwySource _source;

  WiwyPortal get _portal => _source.portal;

  /// Evita pedir la misma estantería dos veces seguidas.
  final Map<int, List<WiwyVodAsset>> _shelves = {};

  /// Subtítulos ya consultados por `contentId`.
  final Map<String, List<ChannelSubtitle>> _subtitles = {};

  List<WiwyVodAsset>? cached(WiwyVodKind kind) => _shelves[kind.columnId];

  Future<List<WiwyVodAsset>> shelf(
    WiwySession session,
    WiwyVodKind kind, {
    bool force = false,
  }) async {
    final cached = _shelves[kind.columnId];
    if (!force && cached != null) return cached;

    final data = await _source.withSession(
      (s) => _portal.getShelveData(s, kind.columnId),
    );
    final assets = <WiwyVodAsset>[];
    for (final item in (data['assetList'] as List?) ?? const []) {
      if (item is! Map) continue;
      final asset = WiwyVodAsset.fromJson(item.cast<String, dynamic>());
      if (asset != null) assets.add(asset);
    }
    _shelves[kind.columnId] = assets;
    return assets;
  }

  /// Búsqueda global del portal (todas las columnas, paginada).
  Future<WiwyVodSearchPage> search(
    WiwySession session,
    String query, {
    int page = 1,
    int pageSize = 40,
  }) async {
    final data = await _source.withSession(
      (s) => _portal.searchByName(s, query, page: page, pageSize: pageSize),
    );

    final assets = <WiwyVodAsset>[];
    final seen = <String>{};
    for (final item in (data['searchItemList'] as List?) ?? const []) {
      if (item is! Map) continue;
      for (final value in (item['itemList'] as List?) ?? const []) {
        if (value is! Map) continue;
        final asset = WiwyVodAsset.fromJson(value.cast<String, dynamic>());
        if (asset == null || !seen.add(asset.contentId)) continue;
        assets.add(asset);
      }
    }

    final total = int.tryParse('${data['totalSize'] ?? ''}') ?? assets.length;
    return WiwyVodSearchPage(assets: assets, total: total);
  }

  Future<WiwyVodDetail> detail(
    WiwySession session,
    WiwyVodKind kind,
    WiwyVodAsset asset,
  ) async {
    final data = await _source.withSession(
      (s) => _portal.getItemData(
        s,
        columnId: kind.columnId,
        contentId: asset.contentId,
        type: asset.type,
      ),
    );

    final info = (data['assetData'] as Map?)?.cast<String, dynamic>() ?? data;
    final episodes = <WiwyVodEpisode>[];
    if (asset.isSeries) {
      for (final item in (info['simpleProgramList'] as List?) ?? const []) {
        if (item is! Map) continue;
        final episode = WiwyVodEpisode.fromJson(item.cast<String, dynamic>());
        if (episode != null) episodes.add(episode);
      }
      episodes.sort((a, b) => a.number.compareTo(b.number));
    }

    final seasons = <WiwyVodSeason>[];
    for (final item in (info['sameSeasonSeriesList'] as List?) ?? const []) {
      if (item is! Map) continue;
      final id = '${item['contentId'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      seasons.add(
        WiwyVodSeason(
          contentId: id,
          number: int.tryParse('${item['seasonNumber'] ?? ''}') ?? 0,
        ),
      );
    }
    seasons.sort((a, b) => a.number.compareTo(b.number));

    final synopsis = '${info['description'] ?? ''}'.trim();
    final releaseTime = '${info['releaseTime'] ?? ''}'.trim();
    return WiwyVodDetail(
      asset: asset,
      synopsis: synopsis.isEmpty ? asset.synopsis : synopsis,
      actors: '${info['actorDisplay'] ?? ''}'.trim(),
      director: '${info['director'] ?? ''}'.trim(),
      year: (releaseTime.isEmpty ? asset.year : releaseTime).split('-').first,
      audio: '${info['audioInfo'] ?? ''}'.trim(),
      episodes: episodes,
      seasons: seasons,
    );
  }

  /// Pide los subtítulos externos del título (o de un capítulo) al portal.
  ///
  /// El servicio del APK usa como `programId` el mismo `contentId` del
  /// catálogo, así que no hace falta resolver el vídeo antes.
  Future<List<ChannelSubtitle>> subtitles(
    WiwyVodAsset asset, {
    WiwyVodEpisode? episode,
  }) async {
    final programId = episode?.contentId ?? asset.contentId;
    final cached = _subtitles[programId];
    if (cached != null) return cached;
    try {
      final result = await _portal.subtitles(programId);
      _subtitles[programId] = result;
      return result;
    } catch (_) {
      // No cacheamos fallos: el próximo intento puede funcionar.
      return const [];
    }
  }

  /// Pide la media del título (o de un capítulo) al portal.
  Future<WiwyVodPlayback?> playback(
    WiwySession session,
    WiwyVodKind kind,
    WiwyVodAsset asset, {
    WiwyVodEpisode? episode,
  }) async {
    final isSeries = episode != null || asset.isSeries;
    final data = await _source.withSession(
      (s) => _portal.startPlayVod(
        s,
        columnId: kind.columnId,
        contentId: episode?.contentId ?? asset.contentId,
        seriesContentId: episode == null ? '' : asset.contentId,
        type: isSeries ? '0' : asset.type,
        episodeNumbers: [episode?.number ?? 1],
      ),
    );

    return WiwyVodPlayback.fromJson(
      data,
      title: asset.name,
      episodeTitle: episode?.name ?? '',
    );
  }
}

/// Reconstruye la URL de un `media_code` VOD sobre los CDN del portal.
///
/// El APK resuelve esta parte con su SDK nativo (`/slb/v11/vod` + nodo P2P),
/// pero los CDN `vod` del portal entregan la media directamente por rangos:
///
/// ```text
/// GET http://<cdn>/vod/<media_code>_media.ts
/// Range: bytes=0-1023        -> 206 video/MP2T
/// ```
///
/// No hace falta firmar la petición: alcanza con el `media_code` que devuelve
/// `v10/startPlayVOD`. El reproductor (libmpv) pide el resto por rangos.
class WiwyVodResolver {
  WiwyVodResolver({
    http.Client? client,
    this.timeout = const Duration(seconds: 6),
    // ignore: prefer_initializing_formals
  }) : _client = client;

  /// Cliente inyectado (pruebas). En la app cada sondeo crea su propio cliente
  /// para respetar los cambios de VPN sin reiniciar la pantalla.
  final http.Client? _client;
  final Duration timeout;

  void close() => _client?.close();

  /// Cabeceras que acompañan a cada intento.
  Map<String, String> headersFor(WiwyCdn cdn, String license) => {
    'User-Agent': WiwyConfig.playerUserAgent,
    'App': WiwyConfig.playerApp,
    'App-Version': WiwyConfig.playerAppVersion,
    'Content-License': license,
  };

  /// Variantes de URL para un `media_code`.
  ///
  /// La primera es la que sirve el CDN VOD real; las demás quedan como
  /// respaldo por si otro CDN expone el manifiesto HLS.
  List<String> candidates(WiwyCdn cdn, String mediaCode, String originalId) {
    final host = cdn.host;
    final ids = <String>{mediaCode, if (originalId.isNotEmpty) originalId};
    final urls = <String>[];
    for (final id in ids) {
      urls
        ..add('http://$host/vod/${id}_media.ts')
        ..add('http://$host/vod/0/$id.m3u8')
        ..add('http://$host/vod/$id.m3u8')
        ..add('http://$host/vod/$id/index.m3u8');
    }
    return urls;
  }

  /// Prueba los CDN disponibles en paralelo y devuelve el que mejor rinde.
  ///
  /// Un sondeo de 1 KB no sirve: algunos CDN responden rápido al primer rango
  /// y luego estrangulan la conexión larga a ~2 Mbit/s (el vídeo de 720p
  /// necesita 2-4 Mbit/s sostenidos y el reproductor entra en bucle de
  /// buffering). Cada CDN se mide descargando unos MB en una sola conexión y
  /// puntuando el tramo final de la descarga; se elige el de mayor
  /// rendimiento sostenido. Si ninguno responde, devuelve `null`.
  ///
  /// Primero se prueba la ruta directa `_media.ts` en todos los CDN; solo si
  /// ninguno responde se prueban las variantes HLS de respaldo.
  Future<Channel?> resolve({
    required List<WiwyCdn> cdns,
    required WiwyVodPlayback media,
  }) async {
    if (cdns.isEmpty) return null;

    final primary = <Future<_CdnScore?>>[
      for (final cdn in cdns)
        _measure(
          'http://${cdn.host}/vod/${media.mediaCode}_media.ts',
          headersFor(cdn, media.license),
          cdn,
        ),
    ];
    var best = _best(await Future.wait(primary));
    if (best != null) return _channelFor(best, media);

    // Respaldo: variantes HLS con el CDN clásico de "primero que responda".
    for (final cdn in cdns) {
      final headers = headersFor(cdn, media.license);
      for (final url in candidates(cdn, media.mediaCode, media.originalId)) {
        if (url.endsWith('/${media.mediaCode}_media.ts')) continue;
        if (!await _probe(url, headers)) continue;
        return _channelForUrl(url, headers, media);
      }
    }
    return null;
  }

  /// Elige el CDN con mejor rendimiento sostenido (los fallidos van al final).
  _CdnScore? _best(List<_CdnScore?> scores) {
    _CdnScore? best;
    for (final score in scores) {
      if (score == null || !score.usable) continue;
      if (best == null || score.kbps > best.kbps) best = score;
    }
    return best;
  }

  Channel _channelFor(_CdnScore score, WiwyVodPlayback media) =>
      _channelForUrl(score.url, score.headers, media);

  Channel _channelForUrl(
    String url,
    Map<String, String> headers,
    WiwyVodPlayback media,
  ) {
    return Channel(
      name: media.episodeTitle.isEmpty
          ? media.title
          : '${media.title} · ${media.episodeTitle}',
      url: url,
      logo: '',
      group: 'Servidor',
      tvgId: media.mediaCode,
      extraHeaders: headers,
      isVod: true,
    );
  }

  /// Genera todas las URLs candidatas para diagnóstico.
  static List<String> allCandidates(List<WiwyCdn> cdns, WiwyVodPlayback media) {
    final urls = <String>[];
    for (final cdn in cdns) {
      urls.addAll(
        WiwyVodResolver().candidates(cdn, media.mediaCode, media.originalId),
      );
    }
    return urls;
  }

  Future<bool> _probe(String url, Map<String, String> headers) async {
    final client = _client ?? ProxySettings.instance.createClient();
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..headers.addAll(headers)
        ..headers['Range'] = 'bytes=0-1023';
      final response = await client
          .send(request)
          .timeout(timeout, onTimeout: () => throw TimeoutException('probe'));
      final ok = response.statusCode == 200 || response.statusCode == 206;
      if (!ok) {
        await response.stream
            .drain<void>()
            .timeout(const Duration(seconds: 2))
            .catchError((_) {});
        return false;
      }
      final type = (response.headers['content-type'] ?? '').toLowerCase();
      if (type.contains('text/html')) {
        await response.stream
            .drain<void>()
            .timeout(const Duration(seconds: 2))
            .catchError((_) {});
        return false;
      }
      var received = 0;
      await for (final chunk in response.stream) {
        received += chunk.length;
        if (received > 256) break;
      }
      return received > 0;
    } catch (_) {
      return false;
    } finally {
      if (_client == null) client.close();
    }
  }

  /// Mide el rendimiento sostenido de una conexión larga al CDN.
  ///
  /// Descarga hasta 3 MB en una sola conexión, aborta a los ~2,5 s y puntúa
  /// los bytes recibidos después del primer segundo: los CDN que entregan una
  /// ráfaga inicial y luego estrangulan la conexión quedan con puntuación baja,
  /// que es justo lo que hunde al reproductor en buffering.
  Future<_CdnScore?> _measure(
    String url,
    Map<String, String> headers,
    WiwyCdn cdn,
  ) async {
    final client = _client ?? ProxySettings.instance.createClient();
    try {
      final request = http.Request('GET', Uri.parse(url))
        ..headers.addAll(headers)
        ..headers['Range'] = 'bytes=0-${3 * 1024 * 1024 - 1}';
      final response = await client.send(request).timeout(timeout);
      final status = response.statusCode;
      final type = (response.headers['content-type'] ?? '').toLowerCase();
      if ((status != 200 && status != 206) || type.contains('text/html')) {
        await response.stream
            .drain<void>()
            .timeout(const Duration(seconds: 2))
            .catchError((_) {});
        return null;
      }

      final sw = Stopwatch()..start();
      var bytes = 0;
      var tailBytes = 0;
      var tailMs = 0;
      var windowOpened = false;
      await for (final chunk in response.stream) {
        bytes += chunk.length;
        final ms = sw.elapsedMilliseconds;
        if (!windowOpened && ms >= _measureRampMs) {
          windowOpened = true;
          tailBytes = 0;
          tailMs = 0;
        }
        if (windowOpened) {
          tailBytes += chunk.length;
          tailMs = ms - _measureRampMs;
        }
        if (ms >= _measureLimitMs || bytes >= 3 * 1024 * 1024) break;
      }
      if (!windowOpened) {
        // Demasiado lento para abrir la ventana: uso el total como puntuación
        // mínima (mejor que descartarlo si es el único que sirve vídeo).
        if (bytes == 0) return null;
        return _CdnScore(
          cdn,
          url,
          headers,
          bytes * 8 / 1000 / sw.elapsedMilliseconds,
        );
      }
      if (tailBytes <= 0 || tailMs <= 0) return null;
      final kbps = tailBytes * 8 / 1000 / tailMs;
      return _CdnScore(cdn, url, headers, kbps);
    } catch (_) {
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }

  /// Cuerpo de la licencia en claro (diagnóstico).
  static String describe(WiwyVodPlayback media) => jsonEncode({
    'media': media.mediaCode,
    'quality': media.quality,
    'format': media.videoFormat,
  });

  /// Milisegundos de "arranque" descartados al puntuar una descarga.
  static const int _measureRampMs = 800;

  /// Duración máxima de la medición por CDN (en paralelo, una vez por título).
  static const int _measureLimitMs = 2500;
}

/// Resultado de medir un CDN: URL probada, cabeceras y kbps sostenidos.
class _CdnScore {
  _CdnScore(this.cdn, this.url, this.headers, this.kbps);

  final WiwyCdn cdn;
  final String url;
  final Map<String, String> headers;

  /// Kilobits por segundo sostenidos tras la ráfaga inicial.
  final double kbps;

  /// ¿Sirvió vídeo y mantuvo flujo durante la medición?
  bool get usable => kbps > 0;
}
