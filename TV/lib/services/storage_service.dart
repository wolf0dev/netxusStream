import 'package:shared_preferences/shared_preferences.dart';

import '../core/accent_theme.dart';
import '../core/app_layout.dart';
import '../core/seasonal_theme.dart';

class StoredPreferences {
  const StoredPreferences({
    required this.favorites,
    required this.mode,
    required this.lastChannelUrl,
    this.useWiwySource = false,
    this.seasonalTheme = SeasonalTheme.auto,
    this.accent = AppAccent.white,
    this.customWallpaperPath,
  });

  final Set<String> favorites;
  final UiModePreference mode;
  final String? lastChannelUrl;
  final bool useWiwySource;
  final SeasonalTheme seasonalTheme;
  final AppAccent accent;
  final String? customWallpaperPath;
}

/// Persistencia local de favoritos y preferencias.
class StorageService {
  static const String _favoritesKey = 'nexus.favorites.v1';
  static const String _modeKey = 'nexus.uiMode.v1';
  static const String _lastChannelKey = 'nexus.lastChannel.v1';
  static const String _sourceKey = 'nexus.source.v1';
  static const String _seasonKey = 'nexus.season.v1';
  static const String _accentKey = 'nexus.accent.v1';
  static const String _wallpaperKey = 'nexus.wallpaper.v1';

  Future<StoredPreferences> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favorites = (prefs.getStringList(_favoritesKey) ?? const <String>[])
          .toSet();
      final rawMode = prefs.getString(_modeKey);
      final mode = UiModePreference.values.firstWhere(
        (value) => value.name == rawMode,
        orElse: () => UiModePreference.auto,
      );
      final rawSeason = prefs.getString(_seasonKey);
      final season = SeasonalTheme.values.firstWhere(
        (value) => value.name == rawSeason,
        orElse: () => SeasonalTheme.auto,
      );
      return StoredPreferences(
        favorites: favorites,
        mode: mode,
        lastChannelUrl: prefs.getString(_lastChannelKey),
        // Primera ejecución: el portal ya funciona sin configuración, así que
        // es la fuente por defecto (el usuario puede apagarlo en Ajustes).
        useWiwySource: prefs.getBool(_sourceKey) ?? true,
        seasonalTheme: season,
        accent: AppAccent.byId(prefs.getString(_accentKey)),
        customWallpaperPath: prefs.getString(_wallpaperKey),
      );
    } catch (_) {
      return const StoredPreferences(
        favorites: <String>{},
        mode: UiModePreference.auto,
        lastChannelUrl: null,
        useWiwySource: true,
      );
    }
  }

  Future<void> saveFavorites(Set<String> favorites) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_favoritesKey, favorites.toList()..sort());
    } catch (_) {
      // Silencioso: los favoritos siguen activos en memoria.
    }
  }

  Future<void> saveMode(UiModePreference mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modeKey, mode.name);
    } catch (_) {
      // Silencioso.
    }
  }

  Future<void> saveLastChannel(String? url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (url == null) {
        await prefs.remove(_lastChannelKey);
      } else {
        await prefs.setString(_lastChannelKey, url);
      }
    } catch (_) {
      // Silencioso.
    }
  }

  Future<void> saveWiwySource(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_sourceKey, enabled);
    } catch (_) {
      // Silencioso.
    }
  }

  Future<void> saveSeasonalTheme(SeasonalTheme theme) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_seasonKey, theme.name);
    } catch (_) {
      // Silencioso.
    }
  }

  Future<void> saveAccent(AppAccent accent) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_accentKey, accent.id);
    } catch (_) {
      // Silencioso.
    }
  }

  Future<void> saveCustomWallpaper(String? path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (path == null || path.isEmpty) {
        await prefs.remove(_wallpaperKey);
      } else {
        await prefs.setString(_wallpaperKey, path);
      }
    } catch (_) {
      // Silencioso.
    }
  }
}
