import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../core/channel_categories.dart';
import '../models/channel.dart';
import 'm3u_parser.dart';
import 'proxy_service.dart';

class PlaylistSnapshot {
  const PlaylistSnapshot({required this.channels, required this.fetchedAt});

  final List<Channel> channels;
  final DateTime fetchedAt;
}

class PlaylistException implements Exception {
  const PlaylistException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'PlaylistException: $message';
}

/// Descarga, parsea y cachea la lista M3U de IPTV-Org.
class M3uService {
  M3uService({http.Client? client})
    : _client = client ?? ProxySettings.instance.createClient();

  static const String playlistUrl = 'https://iptv-org.github.io/iptv/index.m3u';
  static const String _cacheFileName = 'nexusstream_playlist_v1.m3u';
  static const String _espnCacheFileName = 'nexusstream_espn_v1.json';
  static const Duration _timeout = Duration(seconds: 60);
  static const Duration _espnCacheTtl = Duration(hours: 12);

  http.Client _client;

  /// Recrea el cliente para aplicar un cambio de VPN/proxy.
  void resetClient() {
    try {
      _client.close();
    } catch (_) {
      // El cliente anterior puede estar ya cerrado.
    }
    _client = ProxySettings.instance.createClient();
  }

  Future<PlaylistSnapshot> fetchPlaylist() async {
    final source = await _fetchSource(playlistUrl);
    final channels = await compute(parseM3uPlaylist, source);
    if (channels.isEmpty) {
      throw const PlaylistException('No se encontraron canales válidos.');
    }
    unawaited(_writeCache(source));
    return PlaylistSnapshot(channels: channels, fetchedAt: DateTime.now());
  }

  /// Canales ESPN de la lista pública de IPTV-Org.
  ///
  /// Se guardan en una caché propia de 12 horas para no volver a descargar y
  /// parsear el índice completo en cada arranque. Si la descarga falla se usa
  /// la caché anterior aunque haya caducado.
  Future<List<Channel>> fetchEspnChannels({bool force = false}) async {
    if (!force) {
      final cached = await _readEspnCache();
      if (cached != null) return cached;
    }

    try {
      final source = await _fetchSource(playlistUrl);
      final all = await compute(parseM3uPlaylist, source);

      final seen = <String>{};
      final espn = <Channel>[];
      for (final channel in all) {
        if (!ChannelCategories.isEspn(channel.name)) continue;
        if (!seen.add(channel.url)) continue;
        espn.add(channel.copyWith(group: ChannelCategories.deportes));
      }

      if (espn.isNotEmpty) {
        unawaited(_writeEspnCache(espn));
        debugPrint('ESPN añadidos: ${espn.length} canales');
      }
      return List<Channel>.unmodifiable(espn);
    } catch (error) {
      debugPrint('No se pudo actualizar ESPN: $error');
      final cached = await _readEspnCache(allowExpired: true);
      return cached ?? const [];
    }
  }

  Future<String> _fetchSource(String url) async {
    final response = await _client
        .get(
          Uri.parse(url),
          headers: const {
            'Accept': 'audio/x-mpegurl, application/x-mpegURL, text/plain, */*',
            'User-Agent': 'NexusStream/1.0 (Flutter)',
          },
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw PlaylistException(
        'El servidor respondió con el código ${response.statusCode}.',
      );
    }

    final source = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (!source.contains('#EXTINF')) {
      throw const PlaylistException('Formato M3U inválido.');
    }
    return source;
  }

  /// Lee la última lista guardada. Devuelve `null` si no existe o está dañada.
  Future<PlaylistSnapshot?> readCache() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return null;
      final source = await file.readAsString();
      if (source.length < 100 || !source.contains('#EXTINF')) return null;
      final channels = await compute(parseM3uPlaylist, source);
      if (channels.isEmpty) return null;
      final modified = await file.lastModified();
      return PlaylistSnapshot(channels: channels, fetchedAt: modified);
    } catch (error) {
      debugPrint('No se pudo leer la caché M3U: $error');
      return null;
    }
  }

  Future<void> _writeCache(String source) async {
    try {
      final file = await _cacheFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(source, flush: true);
    } catch (error) {
      // La caché es una mejora, nunca debe romper la carga.
      debugPrint('No se pudo guardar la caché M3U: $error');
    }
  }

  Future<File> _cacheFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_cacheFileName');
  }

  Future<File> _espnCacheFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}$_espnCacheFileName',
    );
  }

  Future<List<Channel>?> _readEspnCache({bool allowExpired = false}) async {
    try {
      final file = await _espnCacheFile();
      if (!await file.exists()) return null;
      if (!allowExpired) {
        final modified = await file.lastModified();
        if (DateTime.now().difference(modified) > _espnCacheTtl) return null;
      }

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return null;

      final channels = <Channel>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final name = item['name'];
        final url = item['url'];
        if (name is! String || url is! String || url.isEmpty) continue;
        final headers = item['extraHeaders'];
        channels.add(
          Channel(
            name: name,
            url: url,
            logo: item['logo'] is String ? item['logo'] as String : '',
            group: ChannelCategories.deportes,
            tvgId: item['tvgId'] is String ? item['tvgId'] as String : '',
            userAgent: item['userAgent'] is String
                ? item['userAgent'] as String
                : null,
            referrer: item['referrer'] is String
                ? item['referrer'] as String
                : null,
            extraHeaders: headers is Map
                ? {
                    for (final entry in headers.entries)
                      '${entry.key}': '${entry.value}',
                  }
                : const {},
          ),
        );
      }
      return channels.isEmpty ? null : List<Channel>.unmodifiable(channels);
    } catch (error) {
      debugPrint('No se pudo leer la caché de ESPN: $error');
      return null;
    }
  }

  Future<void> _writeEspnCache(List<Channel> channels) async {
    try {
      final file = await _espnCacheFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode([
          for (final channel in channels)
            {
              'name': channel.name,
              'url': channel.url,
              'logo': channel.logo,
              'tvgId': channel.tvgId,
              'userAgent': channel.userAgent,
              'referrer': channel.referrer,
              'extraHeaders': channel.extraHeaders,
            },
        ]),
        flush: true,
      );
    } catch (error) {
      // La caché es una mejora: si falla, la lista se descarga igualmente.
      debugPrint('No se pudo guardar la caché de ESPN: $error');
    }
  }

  void dispose() => _client.close();
}
