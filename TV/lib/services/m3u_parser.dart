import 'dart:convert';

import '../models/channel.dart';

final RegExp _attributePattern = RegExp(r'([A-Za-z0-9_-]+)="([^"]*)"');

const Set<String> _supportedSchemes = {
  'http',
  'https',
  'rtmp',
  'rtmps',
  'rtsp',
  'rtp',
  'udp',
};

/// Traducciones de los grupos más comunes de IPTV-Org.
const Map<String, String> _groupTranslations = {
  'movies': 'Películas',
  'news': 'Noticias',
  'sports': 'Deportes',
  'music': 'Música',
  'kids': 'Infantil',
  'documentary': 'Documentales',
  'documentaries': 'Documentales',
  'entertainment': 'Entretenimiento',
  'general': 'General',
  'religious': 'Religioso',
  'education': 'Educación',
  'educational': 'Educación',
  'culture': 'Cultura',
  'shop': 'Compras',
  'shopping': 'Compras',
  'travel': 'Viajes',
  'cooking': 'Cocina',
  'family': 'Familia',
  'science': 'Ciencia',
  'weather': 'Clima',
  'business': 'Negocios',
  'auto': 'Motor',
  'comedy': 'Comedia',
  'series': 'Series',
  'anime': 'Anime',
  'animation': 'Animación',
  'lifestyle': 'Estilo de vida',
  'outdoor': 'Aire libre',
  'politics': 'Política',
  'public': 'Público',
  'local': 'Local',
  'regional': 'Regional',
  'classic': 'Clásicos',
  'legislative': 'Legislativo',
  'undefined': 'Otros',
  'xxx': 'Adultos',
  'adult': 'Adultos',
};

/// Parsea el contenido completo de una lista M3U y devuelve sus canales.
///
/// Se ejecuta en un isolate mediante `compute` para no bloquear la interfaz
/// con listas de decenas de miles de entradas.
List<Channel> parseM3uPlaylist(String source) {
  if (source.isEmpty) return const [];

  final lines = const LineSplitter().convert(source);
  final channels = <Channel>[];
  final seen = <String>{};

  var index = 0;
  while (index < lines.length) {
    final line = lines[index].trim();
    if (!line.startsWith('#EXTINF:')) {
      index++;
      continue;
    }

    final attributes = <String, String>{};
    for (final match in _attributePattern.allMatches(line)) {
      attributes[match.group(1)!] = match.group(2)!;
    }

    final name = _extractName(line);
    var userAgent = attributes['http-user-agent'];
    var referrer = attributes['http-referrer'] ?? attributes['http-referer'];
    final extraHeaders = <String, String>{};

    String? url;
    index++;

    while (index < lines.length) {
      final current = lines[index].trim();
      if (current.isEmpty) {
        index++;
        continue;
      }

      if (current.startsWith('#EXTVLCOPT:')) {
        final option = current.substring('#EXTVLCOPT:'.length);
        final separator = option.indexOf('=');
        if (separator > 0) {
          final key = option.substring(0, separator).trim().toLowerCase();
          final value = option.substring(separator + 1).trim();
          if (key == 'http-user-agent' && (userAgent?.isEmpty ?? true)) {
            userAgent = value;
          } else if (key == 'http-referrer' && (referrer?.isEmpty ?? true)) {
            referrer = value;
          } else if (key == 'http-header') {
            // `#EXTVLCOPT:http-header=Content-Auth: valor`
            final colon = value.indexOf(':');
            if (colon > 0) {
              final header = value.substring(0, colon).trim();
              final headerValue = value.substring(colon + 1).trim();
              if (header.isNotEmpty && headerValue.isNotEmpty) {
                extraHeaders[header] = headerValue;
              }
            }
          }
        }
        index++;
        continue;
      }

      if (current.startsWith('#')) {
        // Si empieza otra entrada, el canal actual no tenía URL.
        if (current.startsWith('#EXTINF:')) break;
        index++;
        continue;
      }

      url = current;
      index++;
      break;
    }

    if (url == null || name.isEmpty) continue;

    final uri = Uri.tryParse(url);
    if (uri == null || !_supportedSchemes.contains(uri.scheme.toLowerCase())) {
      continue;
    }

    final group = _cleanGroup(attributes['group-title']);
    final dedupeKey = '${name.toLowerCase()}|$url';
    if (!seen.add(dedupeKey)) continue;

    channels.add(
      Channel(
        name: name,
        url: url,
        logo: attributes['tvg-logo']?.trim() ?? '',
        group: group,
        tvgId: attributes['tvg-id']?.trim() ?? '',
        userAgent: userAgent?.trim(),
        referrer: referrer?.trim(),
        extraHeaders: extraHeaders,
      ),
    );
  }

  return channels;
}

String _extractName(String line) {
  final lastQuote = line.lastIndexOf('"');
  final comma = line.indexOf(',', lastQuote >= 0 ? lastQuote + 1 : 0);
  if (comma < 0) return '';
  var name = line.substring(comma + 1).trim();
  if (name.startsWith('\uFEFF')) name = name.substring(1).trim();
  return name;
}

String _cleanGroup(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return 'Otros';
  final translated = _groupTranslations[value.toLowerCase()];
  return translated ?? value;
}
