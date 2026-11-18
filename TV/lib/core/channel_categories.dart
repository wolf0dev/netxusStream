import '../models/channel.dart';

/// Clasificación de canales por temática.
///
/// El portal WiwyXuper entrega todos los canales en un único grupo (`Wiwy`),
/// así que aquí se deduce la categoría a partir del nombre. Los canales de
/// IPTV-Org que ya traen un grupo válido se respetan y los de ESPN se agrupan
/// siempre en Deportes.
abstract final class ChannelCategories {
  static const String deportes = 'Deportes';
  static const String noticias = 'Noticias';
  static const String cine = 'Cine y Series';
  static const String infantil = 'Infantil';
  static const String anime = 'Anime';
  static const String documentales = 'Documentales';
  static const String musica = 'Música';
  static const String religion = 'Religión';
  static const String cultura = 'Cultura';
  static const String estiloDeVida = 'Estilo de vida';
  static const String negocios = 'Negocios';
  static const String adultos = 'Adultos';
  static const String general = 'General';

  /// Grupos genéricos que deben recalcularse a partir del nombre.
  static const Set<String> _genericGroups = {
    '',
    'Wiwy',
    'Servidor',
    'Otros',
    'General',
    'undefined',
  };

  /// Reglas ordenadas: la primera coincidencia gana.
  ///
  /// El orden importa: «tnt sports» debe ser Deportes antes de que «tnt»
  /// lo clasifique como Cine y Series.
  static const List<(String, List<String>)> _rules = [
    (
      deportes,
      [
        'espn',
        'fox sports',
        'foxsports',
        'dsports',
        'directv sports',
        'directvsports',
        'tnt sports',
        'tntsports',
        'gol',
        'bein',
        'tyc',
        'win sports',
        'nba',
        'nfl',
        'mlb',
        'nhl',
        'f1',
        'formula 1',
        'motogp',
        'ufc',
        'boxeo',
        'box',
        'lucha',
        'wwe',
        'deportes',
        'sports',
        'futbol',
        'liga',
        'copa',
        'champions',
        'premier',
        'eurosport',
        'tenis',
        'golf',
        'pesca',
        'caza',
        'ciclismo',
        'atletismo',
        'olimpiadas',
        'olympic',
      ],
    ),
    (
      noticias,
      [
        'noticias',
        'news',
        'cnn',
        'tn',
        'caracol',
        'rcn',
        'tvn',
        'ecuavisa',
        'france 24',
        'dw',
        'euronews',
        'rt',
        'milenio',
        'foro tv',
        'adn40',
        'azteca noticias',
        '24 horas',
        'telesur',
        'canal n',
        'panamericana',
        'latina',
        'telemundo',
        'univision',
        'bloomberg',
        'cnbc',
        'bbc',
        'sky news',
        'al jazeera',
      ],
    ),
    (
      cine,
      [
        'cine',
        'cinema',
        'cinecanal',
        'movie',
        'pelicula',
        'film',
        'series',
        'serie',
        'hbo',
        'star channel',
        'starchannel',
        'starz',
        'paramount',
        'universal',
        'warner',
        'tnt',
        'space',
        'syfy',
        'amc',
        'sony',
        'axn',
        'fx',
        'golden',
        'mgm',
        'cinemax',
        'showtime',
        'lifetime',
        'comedy central',
        'clasicos',
        'estrenos',
      ],
    ),
    (
      infantil,
      [
        'kids',
        'infantil',
        'cartoon',
        'cartoonnetwork',
        'disney',
        'disneychannel',
        'disneyjunior',
        'nickelodeon',
        'nick',
        'discovery kids',
        'discoverykids',
        'baby',
        'boomerang',
        'tooncast',
        'clan',
        'chicos',
        'ninos',
        'pbs kids',
        'mundo infantil',
      ],
    ),
    (
      anime,
      [
        'anime',
        'otaku',
        'manga',
        'crunchyroll',
        'naruto',
        'dragon ball',
        'one piece',
        'goku',
      ],
    ),
    (
      documentales,
      [
        'documental',
        'documentary',
        'discovery',
        'discoverychannel',
        'history',
        'historychannel',
        'nat geo',
        'national geographic',
        'nationalgeographic',
        'animal planet',
        'animalplanet',
        'investigacion',
        'investigate',
        'science',
        'ciencia',
        'curiosity',
        'insight',
        'planet',
        'naturaleza',
        'wild',
      ],
    ),
    (
      musica,
      [
        'music',
        'musica',
        'mtv',
        'vh1',
        'hits',
        'telehit',
        'bandamax',
        'ritmoson',
        'rock',
        'pop',
        'concierto',
        'clasica',
        'latino',
        'urbano',
      ],
    ),
    (
      religion,
      [
        'dios',
        'religion',
        'religioso',
        'cristo',
        'catolic',
        'evangel',
        'ewtn',
        '3abn',
        'esperanza',
        'iglesia',
        'fe',
        'islam',
        'quran',
        'coran',
        'judio',
      ],
    ),
    (
      cultura,
      [
        'cultura',
        'education',
        'educacion',
        'educa',
        'aprende',
        'universidad',
        'unam',
        'uanl',
        'teatro',
        'arte',
        'museo',
        'viaje',
        'travel',
        'turismo',
      ],
    ),
    (
      estiloDeVida,
      [
        'lifestyle',
        'hogar',
        'home',
        'food',
        'cocina',
        'kitchen',
        'moda',
        'fashion',
        'salud',
        'health',
        'bienestar',
        'belleza',
        'decoracion',
        'jardin',
      ],
    ),
    (
      negocios,
      ['business', 'negocio', 'finanzas', 'economia', 'mercados', 'emprende'],
    ),
    (
      adultos,
      ['adult', 'adultos', 'xxx', 'playboy', 'venus', 'erotico', 'hot', 'sexy'],
    ),
  ];

  static const Map<String, String> _languages = {
    'es': 'Español',
    'en': 'Inglés',
    'pt': 'Portugués',
    'fr': 'Francés',
    'de': 'Alemán',
    'it': 'Italiano',
    'ja': 'Japonés',
    'ko': 'Coreano',
    'zh': 'Chino',
    'ar': 'Árabe',
    'ru': 'Ruso',
    'hi': 'Hindi',
  };

  /// Nombre legible de un idioma ISO-639 (`es`, `en-US`…).
  static String languageName(String? code) {
    final normalized = (code ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return '';
    final base = normalized.split(RegExp(r'[-_]')).first;
    return _languages[base] ?? normalized.toUpperCase();
  }

  /// `true` si el nombre corresponde a un canal de ESPN.
  static bool isEspn(String name) {
    final normalized = _normalize(name);
    return RegExp(r'(^|[^a-z])espn([^a-z]|$)').hasMatch(normalized);
  }

  /// Ajusta la categoría de un canal.
  ///
  /// Los canales de ESPN se agrupan en Deportes aunque la lista de origen los
  /// ponga en otro sitio. Para el resto se conserva el grupo explícito y solo
  /// se deduce la categoría cuando el grupo es genérico (`Wiwy`, `Otros`…).
  static Channel refine(Channel channel) {
    if (isEspn(channel.name)) {
      return channel.group == deportes
          ? channel
          : channel.copyWith(group: deportes);
    }

    final group = channel.group.trim();
    if (!_genericGroups.contains(group)) {
      return channel;
    }

    return channel.copyWith(group: categoryFor(channel.name) ?? general);
  }

  /// Categoría deducida del nombre, o `null` si no encaja en ninguna.
  static String? categoryFor(String name) {
    final normalized = _normalize(name);
    if (isEspn(normalized)) return deportes;

    final padded = ' ${normalized.replaceAll(RegExp(r'[^a-z0-9]+'), ' ')} ';
    for (final rule in _rules) {
      for (final keyword in rule.$2) {
        final needle = _normalize(keyword);
        if (needle.isEmpty) continue;
        // Coincidencia por palabra completa para evitar falsos positivos
        // como «fe» dentro de «telefe» o «rt» dentro de «part».
        if (padded.contains(' $needle ') ||
            RegExp('(^| )${RegExp.escape(needle)}( |[0-9])').hasMatch(padded)) {
          return rule.$1;
        }
      }
    }
    return null;
  }

  static String _normalize(String value) {
    final buffer = StringBuffer();
    for (final rune in value.toLowerCase().runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_replacements[char] ?? char);
    }
    return buffer.toString();
  }

  static const Map<String, String> _replacements = {
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'ã': 'a',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'ê': 'e',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'õ': 'o',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
    'ñ': 'n',
    'ç': 'c',
  };
}
