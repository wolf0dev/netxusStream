import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/accent_theme.dart';
import '../core/app_layout.dart';
import '../core/app_theme.dart';
import '../core/channel_categories.dart';
import '../core/seasonal_theme.dart';
import '../models/channel.dart';
import '../models/vod_resume.dart';
import '../services/m3u_service.dart';
import '../services/proxy_service.dart';
import '../services/resume_service.dart';
import '../services/storage_service.dart';
import '../services/wallpaper_service.dart';
import '../wiwy/wiwy_portal.dart';
import '../wiwy/wiwy_source.dart';

/// Estado global de NexusStream: lista de canales, filtros, favoritos y modo UI.
class AppState extends ChangeNotifier {
  AppState({
    required this.isTvDevice,
    M3uService? service,
    StorageService? storage,
    WallpaperService? wallpaper,
    ResumeService? resume,
    required WiwySource wiwy,
  }) : _service = service ?? M3uService(),
       _storage = storage ?? StorageService(),
       _wallpaper = wallpaper ?? WallpaperService(),
       _resume = resume ?? ResumeService(),
       // ignore: prefer_initializing_formals (el campo es privado)
       _wiwy = wiwy;

  final bool isTvDevice;
  final M3uService _service;
  final StorageService _storage;
  final WallpaperService _wallpaper;
  final ResumeService _resume;
  final WiwySource? _wiwy;

  bool _useWiwy = false;

  List<Channel> _channels = const [];
  List<Channel> _visible = const [];
  List<ChannelCategory> _categories = const [];
  List<Channel> _featured = const [];
  List<Channel> _espnChannels = const [];
  Set<String> _favorites = <String>{};
  List<VodResume> _vodResumes = const <VodResume>[];

  UiModePreference _modePreference = UiModePreference.auto;
  SeasonalTheme _seasonalTheme = SeasonalTheme.auto;
  AppAccent _accent = AppAccent.white;
  String? _customWallpaperPath;
  String? _selectedGroup;
  String _query = '';
  String? _error;
  DateTime? _lastUpdated;
  String? _lastChannelUrl;
  Channel? _lastChannel;

  bool _bootstrapped = false;
  bool _initialLoading = true;
  bool _refreshing = false;
  bool _refreshInFlight = false;
  bool _disposed = false;

  // Getters ------------------------------------------------------------------

  List<Channel> get channels => _channels;
  List<Channel> get visibleChannels => _visible;
  List<ChannelCategory> get categories => _categories;
  List<Channel> get featuredChannels => _featured;
  List<Channel> get favoriteChannels =>
      _channels.where((channel) => isFavorite(channel)).toList(growable: false);

  Set<String> get favorites => _favorites;
  int get favoritesCount => _favorites.length;

  /// Historial de «Continuar viendo», ordenado por actividad reciente.
  List<VodResume> get vodResumes => _vodResumes;

  VodResume? vodResumeFor(String contentId) {
    for (final entry in _vodResumes) {
      if (entry.key == contentId) return entry;
    }
    return null;
  }
  String? get selectedGroup => _selectedGroup;
  String get query => _query;
  String? get errorMessage => _error;
  DateTime? get lastUpdated => _lastUpdated;
  Channel? get lastChannel => _lastChannel;
  UiModePreference get modePreference => _modePreference;

  /// Preferencia de fondo de temporada (automático o fijado por el usuario).
  SeasonalTheme get seasonalThemePreference => _seasonalTheme;

  /// Fondo estacional que debe mostrarse hoy.
  SeasonalTheme get seasonalTheme =>
      SeasonalTheme.resolve(_seasonalTheme, DateTime.now());

  /// Color de énfasis activo en toda la app.
  AppAccent get accent => _accent;

  /// Wallpaper elegido por el usuario (tiene prioridad sobre la temporada).
  String? get customWallpaperPath => _customWallpaperPath;

  bool get isInitialLoading => _initialLoading;
  bool get isRefreshing => _refreshing;
  bool get hasChannels => _channels.isNotEmpty;
  bool get hasError => _error != null && _channels.isNotEmpty;

  /// Fuente activa: lista pública de IPTV-Org o portal de WiwyXuper.
  bool get useWiwy => _useWiwy;
  bool get canUseWiwy => true;

  /// Momento en que caducan las credenciales del portal (si están activas).
  DateTime? get wiwyAuthExpiry => _wiwy?.authExpiresAt;

  /// Fuente del portal, usada por el catálogo VOD.
  WiwySource? get wiwySource => _wiwy;

  AppLayout get layout =>
      resolveLayout(preference: _modePreference, isTvDevice: isTvDevice);

  String get sourceUrl => _useWiwy
      ? 'servidor de canales (refresco automático)'
      : M3uService.playlistUrl;

  String get sourceLabel => _useWiwy ? 'Servidor' : 'IPTV-Org';

  // VPN / proxy ---------------------------------------------------------------

  bool get proxyEnabled => ProxySettings.instance.enabled;
  String get proxyHost => ProxySettings.instance.host;
  int get proxyPort => ProxySettings.instance.port;
  String get proxyAuthority => ProxySettings.instance.authority;

  /// Activa o desactiva el proxy y recrea los clientes para aplicarlo ya.
  Future<void> setProxyEnabled(bool enabled) async {
    await ProxySettings.instance.setEnabled(enabled);
    _wiwy?.refreshNetwork();
    _service.resetClient();
    _notify();
  }

  /// Cambia el servidor del proxy (host y puerto).
  Future<void> setProxyEndpoint(String host, int port) async {
    await ProxySettings.instance.setEndpoint(host, port);
    _wiwy?.refreshNetwork();
    _service.resetClient();
    _notify();
  }

  bool isFavorite(Channel channel) => _favorites.contains(channel.url);

  // Continuar viendo --------------------------------------------------------

  /// Registra (o actualiza) el punto exacto donde se dejó un título.
  ///
  /// [notify] se desactiva al guardar desde `dispose` del reproductor, cuando
  /// el árbol de widgets ya se está desmontando.
  void rememberVodResume(VodResume resume, {bool notify = true}) {
    _vodResumes = ResumeService.organize(_vodResumes, replacement: resume);
    if (notify) _notify();
    unawaited(_resume.save(resume));
  }

  /// Elimina el progreso de un título terminado.
  void clearVodResume(String key, {bool notify = true}) {
    _vodResumes = ResumeService.organize(_vodResumes, removeKey: key);
    if (notify) _notify();
    unawaited(_resume.remove(key));
  }

  // Ciclo de vida ------------------------------------------------------------

  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    final stored = await _storage.load();
    final resumes = await _resume.load();
    _favorites = stored.favorites;
    _vodResumes = resumes;
    _modePreference = stored.mode;
    _seasonalTheme = stored.seasonalTheme;
    _accent = stored.accent;
    AppColors.setAccent(_accent.color);
    _customWallpaperPath = stored.customWallpaperPath;
    _lastChannelUrl = stored.lastChannelUrl;
    _useWiwy = stored.useWiwySource && _wiwy != null;
    _wiwy?.onUpdated = _applyWiwyUpdate;
    _notify();

    if (_useWiwy) {
      await _loadWiwy();
      return;
    }

    final cached = await _service.readCache();
    if (cached != null) {
      _applySnapshot(cached);
      _notify();
      unawaited(refresh(silent: true));
      return;
    }

    await refresh();
  }

  /// Cambia entre la lista pública y el portal de WiwyXuper.
  Future<void> setUseWiwy(bool enabled) async {
    final target = enabled && _wiwy != null;
    if (target == _useWiwy) return;

    _useWiwy = target;
    _channels = const [];
    _visible = const [];
    _categories = const [];
    _featured = const [];
    _selectedGroup = null;
    _error = null;
    _initialLoading = true;
    _notify();
    unawaited(_storage.saveWiwySource(target));

    if (target) {
      await _loadWiwy(force: true);
    } else {
      await refresh();
    }
  }

  /// Garantiza credenciales vigentes antes de abrir un canal del portal.
  ///
  /// Con [force] renueva aunque la caducidad parezca lejana (por si el CDN
  /// invalidó el token antes de tiempo).
  Future<void> ensureFreshStream({bool force = false}) async {
    if (!_useWiwy) return;
    await _wiwy?.ensureFresh(force: force);
  }

  /// Descarga una lista nueva. Si falla y ya hay datos, se conserva la caché.
  Future<void> refresh({bool silent = false}) async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    _refreshing = true;
    _error = null;
    if (!silent || _channels.isEmpty) {
      _initialLoading = _channels.isEmpty;
    }
    _notify();

    try {
      if (_useWiwy) {
        final espnFuture = _loadEspn();
        final playlist = await _wiwy!.refresh();
        await espnFuture;
        _applySnapshot(
          PlaylistSnapshot(
            channels: _withEspn(playlist.channels),
            fetchedAt: playlist.fetchedAt,
          ),
        );
      } else {
        final snapshot = await _service.fetchPlaylist();
        _applySnapshot(snapshot);
      }
      _error = null;
    } on PlaylistException catch (error) {
      _error = error.message;
      debugPrint('Error al actualizar la lista: $error');
    } on WiwyException catch (error) {
      _error = _wiwyMessage(error);
      debugPrint('Error del servidor de canales: $error');
    } catch (error) {
      _error = 'No se pudo actualizar la lista de canales.';
      debugPrint('Error inesperado al actualizar la lista: $error');
    } finally {
      _refreshInFlight = false;
      _refreshing = false;
      _initialLoading = false;
      _notify();
    }
  }

  // Portal Wiwy --------------------------------------------------------------

  Future<void> _loadWiwy({bool force = false}) async {
    final source = _wiwy;
    if (source == null) return;
    _refreshing = true;
    _notify();
    try {
      final espnFuture = _loadEspn();
      final playlist = await source.load(force: force);
      await espnFuture;
      _applySnapshot(
        PlaylistSnapshot(
          channels: _withEspn(playlist.channels),
          fetchedAt: playlist.fetchedAt,
        ),
      );
      _error = null;
    } on WiwyException catch (error) {
      _error = _wiwyMessage(error);
      debugPrint('Error del servidor de canales: $error');
    } catch (error) {
      _error = 'No se pudo cargar la lista del servidor.';
      debugPrint('Error inesperado del servidor: $error');
    } finally {
      _refreshing = false;
      _initialLoading = false;
      _notify();
    }
  }

  /// Llega un refresco automático de credenciales desde el portal.
  void _applyWiwyUpdate(WiwyPlaylist playlist) {
    if (!_useWiwy || _disposed) return;
    _applySnapshot(
      PlaylistSnapshot(
        channels: _withEspn(playlist.channels),
        fetchedAt: playlist.fetchedAt,
      ),
    );
    _notify();
  }

  /// Descarga (o lee de caché) los canales ESPN y los conserva para poder
  /// volver a fusionarlos cuando el portal se actualice en segundo plano.
  Future<void> _loadEspn({bool force = false}) async {
    try {
      final channels = await _service.fetchEspnChannels(force: force);
      if (channels.isNotEmpty) {
        _espnChannels = List<Channel>.unmodifiable(channels);
      }
    } catch (error) {
      debugPrint('Error cargando ESPN: $error');
    }
  }

  /// Une la lista base con los canales ESPN sin repetir URL.
  List<Channel> _withEspn(Iterable<Channel> base) {
    final seen = <String>{};
    final merged = <Channel>[];
    for (final channel in [...base, ..._espnChannels]) {
      if (seen.add(channel.url)) merged.add(channel);
    }
    return merged;
  }

  static String _wiwyMessage(WiwyException error) {
    switch (error.code) {
      case 'portal200001':
        return 'El portal rechazó la versión del cliente (portal200001).';
      case 'timeout':
        return 'El portal tardó demasiado en responder.';
      case 'network':
        return 'No hay conexión con el portal de canales.';
      case 'active':
        return 'El portal no entregó credenciales nuevas.';
      default:
        return 'El portal devolvió un error (${error.code}).';
    }
  }

  // Filtros ------------------------------------------------------------------

  void setGroup(String? group) {
    if (_selectedGroup == group) return;
    _selectedGroup = group;
    _rebuildVisible();
    _notify();
  }

  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    _rebuildVisible();
    _notify();
  }

  void clearFilters() {
    if (_query.isEmpty && _selectedGroup == null) return;
    _query = '';
    _selectedGroup = null;
    _rebuildVisible();
    _notify();
  }

  // Favoritos ----------------------------------------------------------------

  bool toggleFavorite(Channel channel) {
    final removed = _favorites.remove(channel.url);
    if (!removed) _favorites.add(channel.url);
    _notify();
    unawaited(_storage.saveFavorites(_favorites));
    return !removed;
  }

  void clearFavorites() {
    if (_favorites.isEmpty) return;
    _favorites = <String>{};
    _notify();
    unawaited(_storage.saveFavorites(_favorites));
  }

  // Preferencias -------------------------------------------------------------

  void setModePreference(UiModePreference value) {
    if (_modePreference == value) return;
    _modePreference = value;
    _notify();
    unawaited(_storage.saveMode(value));
  }

  void setSeasonalTheme(SeasonalTheme value) {
    final previousWallpaper = _customWallpaperPath;
    if (_seasonalTheme == value && previousWallpaper == null) return;
    _seasonalTheme = value;
    _customWallpaperPath = null;
    _notify();
    unawaited(_storage.saveSeasonalTheme(value));
    if (previousWallpaper != null) {
      unawaited(_storage.saveCustomWallpaper(null));
      unawaited(_wallpaper.remove(previousWallpaper));
    }
  }

  Future<void> setAccent(AppAccent value) async {
    if (_accent == value) return;
    _accent = value;
    AppColors.setAccent(value.color);
    _notify();
    await _storage.saveAccent(value);
  }

  /// Abre el selector nativo de imágenes y guarda una copia en la app.
  /// Devuelve `true` si el usuario eligió una imagen válida.
  Future<bool> pickCustomWallpaper() async {
    try {
      final path = await _wallpaper.pickAndStore();
      if (path == null) return false;
      final previous = _customWallpaperPath;
      _customWallpaperPath = path;
      _notify();
      await _storage.saveCustomWallpaper(path);
      if (previous != null && previous != path) {
        unawaited(_wallpaper.remove(previous));
      }
      return true;
    } catch (error) {
      debugPrint('No se pudo cargar la imagen de fondo: $error');
      return false;
    }
  }

  Future<void> clearCustomWallpaper() async {
    final path = _customWallpaperPath;
    if (path == null) return;
    _customWallpaperPath = null;
    _notify();
    await _storage.saveCustomWallpaper(null);
    unawaited(_wallpaper.remove(path));
  }

  void rememberChannel(Channel channel) {
    _lastChannel = channel;
    _lastChannelUrl = channel.url;
    _notify();
    unawaited(_storage.saveLastChannel(channel.url));
  }

  void dismissError() {
    if (_error == null) return;
    _error = null;
    _notify();
  }

  // Internos -----------------------------------------------------------------

  void _applySnapshot(PlaylistSnapshot snapshot) {
    // Deduplica por URL y afina la categoría (Wiwy llega todo como «Wiwy»
    // y los canales ESPN deben quedar siempre en Deportes).
    final seen = <String>{};
    final normalized = <Channel>[];
    for (final channel in snapshot.channels) {
      if (!seen.add(channel.url)) continue;
      normalized.add(ChannelCategories.refine(channel));
    }

    _channels = List<Channel>.unmodifiable(normalized);
    _categories = List<ChannelCategory>.unmodifiable(
      buildCategories(_channels),
    );
    _featured = List<Channel>.unmodifiable(_pickFeatured(_channels));
    _lastUpdated = snapshot.fetchedAt;
    _initialLoading = false;

    if (_selectedGroup != null &&
        !_categories.any((category) => category.name == _selectedGroup)) {
      _selectedGroup = null;
    }

    final lastUrl = _lastChannel?.url ?? _lastChannelUrl;
    if (lastUrl != null) {
      _lastChannel = _findByUrl(lastUrl);
    }

    _rebuildVisible();
  }

  void _rebuildVisible() {
    final group = _selectedGroup;
    final needle = _query.trim().toLowerCase();
    _visible = List<Channel>.unmodifiable(
      _channels.where((channel) {
        if (group != null && channel.group != group) return false;
        if (needle.isNotEmpty && !channel.searchIndex.contains(needle)) {
          return false;
        }
        return true;
      }),
    );
  }

  Channel? _findByUrl(String url) {
    for (final channel in _channels) {
      if (channel.url == url) return channel;
    }
    return null;
  }

  static List<Channel> _pickFeatured(List<Channel> channels) {
    const limit = 14;
    final featured = <Channel>[];
    final usedGroups = <String>{};
    final usedUrls = <String>{};

    for (final channel in channels) {
      if (!channel.hasLogo) continue;
      if (!usedGroups.add(channel.group)) continue;
      if (!usedUrls.add(channel.url)) continue;
      featured.add(channel);
      if (featured.length >= limit) return featured;
    }

    for (final channel in channels) {
      if (!channel.hasLogo) continue;
      if (!usedUrls.add(channel.url)) continue;
      featured.add(channel);
      if (featured.length >= limit) break;
    }

    return featured;
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _service.dispose();
    _wiwy?.dispose();
    super.dispose();
  }
}
