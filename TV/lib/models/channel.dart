import '../core/network_defaults.dart';

/// Subtítulo externo (SRT/VTT) asociado a una película o capítulo.
///
/// El portal de Wiwy entrega los subtítulos aparte del `.ts`, así que se
/// descargan como pista externa del reproductor.
class ChannelSubtitle {
  const ChannelSubtitle({
    required this.url,
    this.language = '',
    this.label = '',
    this.format = 'srt',
  });

  final String url;

  /// Código ISO del idioma (`es`, `en`, …).
  final String language;

  /// Nombre para mostrar; si está vacío se deduce del idioma.
  final String label;

  /// Extensión del archivo (`srt`, `vtt`, …).
  final String format;

  bool get isSrt => format.toLowerCase() == 'srt';
}

/// Un canal de una lista M3U (IPTV-Org o portal WiwyXuper).
class Channel {
  Channel({
    required this.name,
    required this.url,
    this.logo = '',
    this.group = 'Otros',
    this.tvgId = '',
    this.userAgent,
    this.referrer,
    this.extraHeaders = const {},
    this.headerResolver,
    this.isVod = false,
    this.subtitles = const [],
  }) : searchIndex = _buildSearchIndex(name, group);

  final String name;
  final String url;
  final String logo;
  final String group;
  final String tvgId;

  /// Cabeceras HTTP opcionales declaradas en la lista (`http-user-agent`,
  /// `#EXTVLCOPT:http-user-agent`, etc.).
  final String? userAgent;
  final String? referrer;

  /// Cabeceras adicionales (por ejemplo `Content-Auth` del portal Wiwy).
  final Map<String, String> extraHeaders;

  /// Fuente de cabeceras que pueden cambiar con el tiempo (tokens que se
  /// refrescan en segundo plano). Se consulta en cada reproducción.
  final Map<String, String> Function()? headerResolver;

  /// `true` para una película o capítulo del catálogo VOD: no depende de las
  /// credenciales de directo, así que el reproductor no las renueva.
  final bool isVod;

  /// Subtítulos externos que acompañan al título (solo VOD).
  final List<ChannelSubtitle> subtitles;

  /// Texto precalculado para búsquedas rápidas.
  final String searchIndex;

  static String _buildSearchIndex(String name, String group) =>
      '${name.toLowerCase()} ${group.toLowerCase()}';

  /// Copia el canal cambiando solo lo indicado (por ejemplo, la categoría).
  Channel copyWith({
    String? name,
    String? url,
    String? logo,
    String? group,
    String? tvgId,
    String? userAgent,
    String? referrer,
    Map<String, String>? extraHeaders,
    Map<String, String> Function()? headerResolver,
    bool? isVod,
    List<ChannelSubtitle>? subtitles,
  }) {
    return Channel(
      name: name ?? this.name,
      url: url ?? this.url,
      logo: logo ?? this.logo,
      group: group ?? this.group,
      tvgId: tvgId ?? this.tvgId,
      userAgent: userAgent ?? this.userAgent,
      referrer: referrer ?? this.referrer,
      extraHeaders: extraHeaders ?? this.extraHeaders,
      headerResolver: headerResolver ?? this.headerResolver,
      isVod: isVod ?? this.isVod,
      subtitles: subtitles ?? this.subtitles,
    );
  }

  bool get hasLogo => logo.trim().isNotEmpty;

  /// Iniciales para el placeholder cuando el logo no carga.
  String get initials {
    final words = name
        .replaceAll(RegExp(r'[^\p{L}\p{N} ]', unicode: true), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return 'TV';
    if (words.length == 1) {
      final word = words.first;
      return word.substring(0, word.length > 1 ? 2 : 1).toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  /// Cabeceras HTTP del stream.
  ///
  /// Siempre incluye un `User-Agent` de navegador (o el declarado por el
  /// canal) para evitar que los CDN rechacen la conexión por considerar al
  /// reproductor un cliente desconocido. Después se superponen las cabeceras
  /// propias del canal (`extraHeaders` y `headerResolver`).
  ///
  /// No se incluye `Host`: la URL ya apunta al CDN correcto y reenviarlo a los
  /// segmentos (que viven en otro host) hace que devuelvan 0 bytes.
  Map<String, String> get httpHeaders {
    final headers = NetworkDefaults.streamHeaders(
      userAgent: userAgent,
      referrer: referrer,
    );
    final overrides = <String, String>{
      ...extraHeaders,
      ...?headerResolver?.call(),
    };
    overrides.removeWhere(
      (key, value) => key.trim().isEmpty || value.trim().isEmpty,
    );
    headers.addAll(overrides);
    return headers;
  }

  @override
  String toString() => 'Channel($name, $group)';
}

/// Categoría (grupo) con su cantidad de canales.
class ChannelCategory {
  const ChannelCategory({required this.name, required this.count});

  final String name;
  final int count;
}

/// Construye y ordena las categorías por cantidad de canales.
List<ChannelCategory> buildCategories(Iterable<Channel> channels) {
  final counts = <String, int>{};
  for (final channel in channels) {
    counts.update(channel.group, (value) => value + 1, ifAbsent: () => 1);
  }
  final categories = counts.entries
      .map((entry) => ChannelCategory(name: entry.key, count: entry.value))
      .toList();
  categories.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    return byCount != 0 ? byCount : a.name.compareTo(b.name);
  });
  return categories;
}
