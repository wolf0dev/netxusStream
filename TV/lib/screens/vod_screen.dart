import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_layout.dart';
import '../core/app_scope.dart';
import '../core/app_theme.dart';
import '../models/vod_resume.dart';
import '../widgets/feedback.dart';
import '../widgets/neon_spinner.dart';
import '../widgets/nexus_focusable.dart';
import '../widgets/search_field.dart';
import '../wiwy/wiwy_portal.dart';
import '../wiwy/wiwy_source.dart';
import '../wiwy/wiwy_vod.dart';
import 'player_screen.dart';

/// Catálogo de películas y series del portal WiwyXuper.
class VodScreen extends StatefulWidget {
  const VodScreen({super.key, required this.layout});

  final AppLayout layout;

  @override
  State<VodScreen> createState() => _VodScreenState();
}

class _VodScreenState extends State<VodScreen> {
  WiwyVodKind _kind = WiwyVodKind.movies;
  List<WiwyVodAsset>? _assets;
  String? _error;
  bool _loading = false;
  bool _bootstrapped = false;

  final TextEditingController _search = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';
  List<_VodHit>? _hits;
  String? _searchError;
  bool _searching = false;
  bool _loadingMore = false;
  int _searchTotal = 0;
  int _searchPage = 1;
  int _searchToken = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    final source = AppScope.read(context).wiwySource;
    if (source == null) {
      setState(() {
        _error = 'Activa el servidor de canales en Ajustes para ver el catálogo.';
        _loading = false;
      });
      return;
    }

    final kind = _kind;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final session = await source.ensureSession();
      final assets = await source.vod.shelf(session, kind, force: force);
      if (!mounted || kind != _kind) return;
      setState(() {
        _assets = assets;
        _loading = false;
      });
    } on WiwyException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _message(error);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el catálogo ($error).';
        _loading = false;
      });
    }
  }

  void _selectKind(WiwyVodKind kind) {
    if (kind == _kind) return;
    _searchDebounce?.cancel();
    _search.clear();
    setState(() {
      _kind = kind;
      _assets = null;
      _error = null;
      _query = '';
      _hits = null;
      _searchError = null;
      _searching = false;
      _loadingMore = false;
      _searchTotal = 0;
      _searchPage = 1;
    });
    unawaited(_load());
  }

  // ------------------------------------------------------------- búsqueda

  void _onQueryChanged(String value) {
    final text = value.trim();
    debugPrint('VOD búsqueda: "$text"');
    _searchDebounce?.cancel();
    _searchToken++;
    if (text.isEmpty) {
      setState(() {
        _query = '';
        _hits = null;
        _searchError = null;
        _searching = false;
        _loadingMore = false;
        _searchTotal = 0;
        _searchPage = 1;
      });
      return;
    }
    setState(() {
      _query = text;
      _searchError = null;
      _searching = true;
      _loadingMore = false;
      _hits = null;
      _searchTotal = 0;
      _searchPage = 1;
    });
    _searchDebounce = Timer(
      const Duration(milliseconds: 320),
      () => unawaited(_runSearch(text)),
    );
  }

  /// Busca en todo el catálogo del portal (no solo en lo ya cargado).
  Future<void> _runSearch(String query, {int page = 1}) async {
    final source = AppScope.read(context).wiwySource;
    if (source == null) return;

    final token = ++_searchToken;
    setState(() {
      if (page == 1) {
        _searching = true;
      } else {
        _loadingMore = true;
      }
      _searchError = null;
    });

    try {
      final session = await source.ensureSession();
      final result = await source.vod.search(session, query, page: page);
      if (!mounted || token != _searchToken) return;

      final hits = <_VodHit>[];
      final seen = <String>{};
      if (page > 1) {
        for (final hit in _hits ?? const <_VodHit>[]) {
          if (seen.add(hit.asset.contentId)) hits.add(hit);
        }
      }
      for (final asset in result.assets) {
        if (!seen.add(asset.contentId)) continue;
        hits.add(
          _VodHit(
            asset.isSeries ? WiwyVodKind.series : WiwyVodKind.movies,
            asset,
          ),
        );
      }

      setState(() {
        _hits = hits;
        _searchTotal = result.total;
        _searchPage = page;
        _searching = false;
        _loadingMore = false;
      });
      debugPrint(
        'Búsqueda VOD "$query" p$page: ${result.assets.length} '
        '(${hits.length}/${result.total})',
      );
    } catch (error) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _searchError = 'No se pudo buscar en el catálogo ($error).';
        _searching = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _refresh() async {
    if (_query.isEmpty) {
      await _load(force: true);
      return;
    }
    await _runSearch(_query);
  }

  Future<void> _open(
    WiwyVodAsset asset, {
    WiwyVodKind? kind,
    VodResume? resume,
    bool autoPlay = false,
  }) async {
    final source = AppScope.read(context).wiwySource;
    if (source == null) return;
    debugPrint(
      'VOD abrir: ${asset.name} [${(kind ?? _kind).label}] ${asset.contentId}',
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VodDetailPage(
          layout: widget.layout,
          kind: kind ?? _kind,
          asset: asset,
          source: source,
          initialResume: resume,
          autoPlayResume: autoPlay,
        ),
      ),
    );
  }

  /// Reanuda un título directamente desde «Continuar viendo»: se abre la ficha
  /// y, en cuanto carga, entra en el reproductor en el punto guardado.
  Future<void> _openResume(VodResume resume) => _open(
    resume.asset,
    kind: resume.kind,
    resume: resume,
    autoPlay: true,
  );

  static String _message(WiwyException error) {
    switch (error.code) {
      case 'portal200001':
        return 'El portal rechazó la versión del cliente.';
      case 'timeout':
        return 'El portal tardó demasiado en responder.';
      case 'network':
        return 'Sin conexión con el servidor de canales.';
      default:
        return 'El portal devolvió un error (${error.code}).';
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    final padding = layout.pagePadding;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        padding,
        layout.isPhone ? 14 : 24,
        padding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            layout: layout,
            kind: _kind,
            onKind: _selectKind,
            onRefresh: () => unawaited(_refresh()),
            loading: _loading || _searching,
            subtitle: _subtitle,
            search: _search,
            onQuery: _onQueryChanged,
          ),
          const SizedBox(height: 16),
          Expanded(child: _body(AppScope.of(context).vodResumes)),
        ],
      ),
    );
  }

  String get _subtitle {
    if (_query.isNotEmpty) {
      if (_searching) return 'Buscando «$_query»…';
      final total = _searchTotal;
      if (total == 0) return 'Sin resultados para «$_query»';
      return 'Resultados · $total ${total == 1 ? 'título' : 'títulos'}';
    }
    final assets = _assets;
    if (assets == null) return 'Películas y series del servidor';
    return '${_kind.label} · ${assets.length} títulos';
  }

  Widget _body(List<VodResume> resumes) {
    if (_query.isNotEmpty) return _searchBody();

    if (_loading && _assets == null) {
      return const Center(child: NeonSpinner());
    }

    final error = _error;
    if (error != null) {
      return ErrorState(message: error, onRetry: () => unawaited(_load()));
    }

    final assets = _assets ?? const <WiwyVodAsset>[];
    if (assets.isEmpty) {
      return EmptyState(
        icon: Icons.movie_filter_outlined,
        title: 'Sin títulos',
        message: 'Este apartado no tiene títulos por ahora.',
        actionLabel: 'Actualizar',
        onAction: () => unawaited(_load(force: true)),
      );
    }

    return _catalog(assets, resumes);
  }

  /// Portada del catálogo: continuar viendo, destacados y filas por categoría.
  ///
  /// Los tags del portal llegan en inglés (`Drama`, `Thriller`, `Animation`…),
  /// así que se traducen solo para mostrarlos. Cada título puede aparecer en
  /// varias filas si el portal le asigna varios géneros; las categorías con un
  /// único título se agrupan al final en «Más títulos» para no dejar filas de
  /// una sola tarjeta.
  Widget _catalog(List<WiwyVodAsset> assets, List<VodResume> resumes) {
    final featured = _featuredFor(assets);
    final groups = _groupsFor(assets);
    final rows = groups.where((group) => group.assets.length > 1).toList();
    final shown = <String>{
      for (final group in rows)
        for (final asset in group.assets) asset.contentId,
    };
    final extras = [
      for (final asset in assets)
        if (!shown.contains(asset.contentId)) asset,
    ];

    return ListView(
      padding: const EdgeInsets.only(bottom: 36),
      children: [
        if (resumes.isNotEmpty) ...[
          _CategoryHeader(title: 'Continuar viendo', count: resumes.length),
          const SizedBox(height: 10),
          _ResumeRow(
            layout: widget.layout,
            resumes: resumes,
            onOpen: _openResume,
          ),
          const SizedBox(height: 26),
        ],
        if (featured.isNotEmpty) ...[
          _FeaturedCarousel(
            key: ValueKey(_kind),
            assets: featured,
            layout: widget.layout,
            onOpen: (asset) => unawaited(_open(asset)),
          ),
          const SizedBox(height: 26),
        ],
        for (final group in rows) ...[
          _CategoryHeader(title: group.label, count: group.assets.length),
          const SizedBox(height: 10),
          _CategoryRow(
            layout: widget.layout,
            assets: group.assets,
            onOpen: (asset) => unawaited(_open(asset)),
          ),
          const SizedBox(height: 26),
        ],
        if (extras.isNotEmpty) ...[
          _CategoryHeader(title: 'Más títulos', count: extras.length),
          const SizedBox(height: 10),
          _CategoryRow(
            layout: widget.layout,
            assets: extras,
            onOpen: (asset) => unawaited(_open(asset)),
          ),
          const SizedBox(height: 26),
        ],
        _CategoryHeader(
          title: 'Todo el catálogo',
          count: assets.length,
          muted: true,
        ),
        const SizedBox(height: 10),
        _grid(
          [for (final asset in assets) _VodHit(_kind, asset)],
          nested: true,
          padding: EdgeInsets.zero,
        ),
      ],
    );
  }

  /// Títulos para el carrusel: primero los mejor valorados con imagen ancha.
  static List<WiwyVodAsset> _featuredFor(List<WiwyVodAsset> assets) {
    final sorted = [...assets]
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        return b.year.compareTo(a.year);
      });
    final wide = sorted
        .where((asset) => asset.backdrop.isNotEmpty)
        .take(8)
        .toList();
    if (wide.length >= 5) return wide;
    for (final asset in sorted) {
      if (wide.any((item) => item.contentId == asset.contentId)) continue;
      wide.add(asset);
      if (wide.length >= 8) break;
    }
    return wide;
  }

  /// Agrupa por género conservando el orden de popularidad.
  static List<_VodGroup> _groupsFor(List<WiwyVodAsset> assets) {
    final map = <String, List<WiwyVodAsset>>{};
    for (final asset in assets) {
      for (final genre in _genresOf(asset)) {
        map.putIfAbsent(genre, () => <WiwyVodAsset>[]).add(asset);
      }
    }
    final groups = [
      for (final entry in map.entries)
        _VodGroup(label: entry.key, assets: entry.value),
    ];
    groups.sort((a, b) {
      final byCount = b.assets.length.compareTo(a.assets.length);
      return byCount != 0 ? byCount : a.label.compareTo(b.label);
    });
    return groups;
  }

  /// Géneros legibles de un título (`Animation · Family` → `Animación · Familiar`).
  static List<String> _genresOf(WiwyVodAsset asset) {
    final genres = <String>[];
    for (final raw in asset.tags.split('·')) {
      final value = raw.trim();
      if (value.isEmpty) continue;
      final label = _genreLabels[value.toLowerCase()] ?? value;
      if (!genres.contains(label)) genres.add(label);
    }
    return genres;
  }

  Widget _searchBody() {
    if (_searching && _hits == null) {
      return const Center(child: NeonSpinner());
    }

    final error = _searchError;
    if (error != null) {
      return ErrorState(
        message: error,
        onRetry: () => unawaited(_runSearch(_query)),
      );
    }

    final hits = _hits ?? const <_VodHit>[];
    if (hits.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Sin resultados',
        message: 'No encontramos títulos que coincidan con «$_query».',
        actionLabel: 'Limpiar búsqueda',
        onAction: () {
          _search.clear();
          _onQueryChanged('');
        },
      );
    }

    final hasMore = hits.length < _searchTotal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _grid(hits)),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 16),
            child: Center(
              child: NexusFocusable(
                onTap: () {
                  if (_loadingMore) return;
                  unawaited(_runSearch(_query, page: _searchPage + 1));
                },
                borderRadius: const BorderRadius.all(Radius.circular(12)),
                semanticLabel: 'Cargar más resultados',
                builder: (context, focused, hovered) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: const BorderRadius.all(Radius.circular(12)),
                    border: Border.all(
                      color: focused || hovered
                          ? AppColors.cyan
                          : AppColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_loadingMore) ...[
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Text(
                        _loadingMore
                            ? 'Cargando…'
                            : 'Cargar más · ${_searchTotal - hits.length} restantes',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _grid(
    List<_VodHit> hits, {
    bool nested = false,
    EdgeInsetsGeometry? padding,
  }) {
    return GridView.builder(
      padding: padding ?? const EdgeInsets.only(bottom: 32),
      shrinkWrap: nested,
      physics: nested ? const NeverScrollableScrollPhysics() : null,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 210,
        mainAxisSpacing: 18,
        crossAxisSpacing: 16,
        childAspectRatio: 0.56,
      ),
      itemCount: hits.length,
      itemBuilder: (context, index) {
        final hit = hits[index];
        return _PosterCard(
          asset: hit.asset,
          badge: _query.isEmpty ? null : hit.kind.label,
          onTap: () => unawaited(_open(hit.asset, kind: hit.kind)),
        );
      },
    );
  }
}

/// Título encontrado en el catálogo y la sección a la que pertenece.
class _VodHit {
  const _VodHit(this.kind, this.asset);

  final WiwyVodKind kind;
  final WiwyVodAsset asset;
}

/// Fila del catálogo agrupada por género.
class _VodGroup {
  const _VodGroup({required this.label, required this.assets});

  final String label;
  final List<WiwyVodAsset> assets;
}

/// Géneros del portal traducidos para la interfaz.
const Map<String, String> _genreLabels = {
  'action': 'Acción',
  'adventure': 'Aventura',
  'animation': 'Animación',
  'anime': 'Anime',
  'biography': 'Biografía',
  'comedy': 'Comedia',
  'crime': 'Crimen',
  'documentary': 'Documentales',
  'drama': 'Drama',
  'family': 'Familiar',
  'fantasy': 'Fantasía',
  'history': 'Historia',
  'horror': 'Terror',
  'music': 'Música',
  'musical': 'Musical',
  'mystery': 'Misterio',
  'romance': 'Romance',
  'sci-fi': 'Ciencia ficción',
  'science fiction': 'Ciencia ficción',
  'short': 'Cortos',
  'sport': 'Deporte',
  'thriller': 'Suspense',
  'war': 'Guerra',
  'western': 'Western',
  'kids': 'Infantil',
  'reality': 'Reality',
  'talk': 'Talk show',
  'soap': 'Telenovela',
  'news': 'Noticias',
};

// ------------------------------------------------------- carrusel de portada

class _FeaturedCarousel extends StatefulWidget {
  const _FeaturedCarousel({
    super.key,
    required this.assets,
    required this.layout,
    required this.onOpen,
  });

  final List<WiwyVodAsset> assets;
  final AppLayout layout;
  final ValueChanged<WiwyVodAsset> onOpen;

  @override
  State<_FeaturedCarousel> createState() => _FeaturedCarouselState();
}

class _FeaturedCarouselState extends State<_FeaturedCarousel> {
  late final PageController _controller;
  Timer? _timer;
  int _index = 0;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _controller = PageController(
      viewportFraction: switch (widget.layout) {
        AppLayout.phone => 0.9,
        AppLayout.tv => 0.66,
        AppLayout.desktop => 0.58,
      },
    );
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    // En Android TV el autoavance pelea con la navegación por D-pad.
    if (widget.layout.isTv || widget.assets.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted || _paused || !_controller.hasClients) return;
      _go(1);
    });
  }

  void _go(int delta) {
    if (!_controller.hasClients) return;
    final count = widget.assets.length;
    final next = (_index + delta + count) % count;
    _controller.animateToPage(
      next,
      duration: const Duration(milliseconds: 460),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.layout.isPhone ? 216.0 : 300.0;
    final wide = !widget.layout.isPhone;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: MouseRegion(
            onEnter: (_) => _paused = true,
            onExit: (_) => _paused = false,
            child: Listener(
              onPointerDown: (_) => _paused = true,
              onPointerUp: (_) => _paused = false,
              child: Stack(
                children: [
                  PageView.builder(
                    controller: _controller,
                    padEnds: false,
                    allowImplicitScrolling: true,
                    itemCount: widget.assets.length,
                    onPageChanged: (value) => setState(() => _index = value),
                    itemBuilder: (context, index) {
                      final asset = widget.assets[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _FeaturedCard(
                          asset: asset,
                          onTap: () => widget.onOpen(asset),
                        ),
                      );
                    },
                  ),
                  if (wide) ...[
                    Positioned(
                      left: 4,
                      top: height / 2 - 22,
                      child: _CarouselArrow(
                        icon: Icons.chevron_left_rounded,
                        label: 'Destacado anterior',
                        onTap: () => _go(-1),
                      ),
                    ),
                    Positioned(
                      right: 16,
                      top: height / 2 - 22,
                      child: _CarouselArrow(
                        icon: Icons.chevron_right_rounded,
                        label: 'Siguiente destacado',
                        onTap: () => _go(1),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < widget.assets.length; index++)
              GestureDetector(
                onTap: () {
                  if (!_controller.hasClients) return;
                  _controller.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: index == _index ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: index == _index
                        ? AppColors.cyan
                        : Colors.white.withValues(alpha: 0.24),
                    borderRadius: const BorderRadius.all(Radius.circular(99)),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.asset, required this.onTap});

  final WiwyVodAsset asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final genres = _VodScreenState._genresOf(asset).join(' · ');
    final meta = <String>[
      if (asset.score > 0) '★ ${asset.score.toStringAsFixed(1)}',
      if (asset.year.isNotEmpty) asset.year,
      if (asset.duration.isNotEmpty) asset.duration,
      if (asset.isSeries && asset.episodeCount > 0)
        '${asset.episodeCount} capítulos',
    ];

    return NexusFocusable(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      focusedScale: 1.012,
      semanticLabel: 'Destacado: ${asset.name}',
      builder: (context, focused, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(20)),
          border: Border.all(
            color: focused
                ? AppColors.cyan
                : hovered
                ? AppColors.cyan.withValues(alpha: 0.42)
                : AppColors.border,
            width: focused ? 2 : 1,
          ),
          boxShadow: focused
              ? [
                  BoxShadow(
                    color: AppColors.glow(0.26),
                    blurRadius: 30,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _PosterImage(
              url: asset.backdrop.isNotEmpty ? asset.backdrop : asset.poster,
              name: asset.name,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x12000000),
                    Color(0x66000000),
                    Color(0xF2000000),
                  ],
                  stops: [0, 0.46, 1],
                ),
              ),
            ),
            Positioned(
              top: 14,
              left: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.cyan,
                  borderRadius: const BorderRadius.all(Radius.circular(99)),
                ),
                child: Text(
                  'DESTACADO',
                  style: TextStyle(
                    color: AppColors.onAccent,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (genres.isNotEmpty)
                    Text(
                      genres.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.cyan,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  const SizedBox(height: 5),
                  Text(
                    asset.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      height: 1.08,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      meta.join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.cyan,
                        ),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: 19,
                          color: AppColors.onAccent,
                        ),
                      ),
                      const SizedBox(width: 9),
                      const Text(
                        'Ver ficha',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CarouselArrow extends StatelessWidget {
  const _CarouselArrow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NexusFocusable(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(99)),
      semanticLabel: label,
      builder: (context, focused, hovered) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: hovered ? 0.68 : 0.5),
          border: Border.all(
            color: focused
                ? AppColors.cyan
                : Colors.white.withValues(alpha: 0.16),
          ),
        ),
        child: Icon(icon, size: 26, color: Colors.white),
      ),
    );
  }
}

// ------------------------------------------------------------ filas y títulos

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({
    required this.title,
    required this.count,
    this.muted = false,
  });

  final String title;
  final int count;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: muted ? 15 : 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: muted ? AppColors.textMuted : AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.all(Radius.circular(99)),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.layout,
    required this.assets,
    required this.onOpen,
  });

  final AppLayout layout;
  final List<WiwyVodAsset> assets;
  final ValueChanged<WiwyVodAsset> onOpen;

  @override
  Widget build(BuildContext context) {
    final phone = layout.isPhone;
    final height = phone ? 206.0 : 252.0;
    final width = phone ? 116.0 : 150.0;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 4),
        itemCount: assets.length,
        separatorBuilder: (_, _) => SizedBox(width: phone ? 10 : 14),
        itemBuilder: (context, index) {
          final asset = assets[index];
          return SizedBox(
            width: width,
            child: _PosterCard(
              asset: asset,
              onTap: () => onOpen(asset),
            ),
          );
        },
      ),
    );
  }
}

/// Fila horizontal con el punto exacto donde se dejó cada título.
class _ResumeRow extends StatelessWidget {
  const _ResumeRow({
    required this.layout,
    required this.resumes,
    required this.onOpen,
  });

  final AppLayout layout;
  final List<VodResume> resumes;
  final ValueChanged<VodResume> onOpen;

  @override
  Widget build(BuildContext context) {
    final phone = layout.isPhone;
    final width = phone ? 224.0 : 272.0;
    final height = phone ? 124.0 : 138.0;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 4),
        itemCount: resumes.length,
        separatorBuilder: (_, _) => SizedBox(width: phone ? 10 : 14),
        itemBuilder: (context, index) {
          final resume = resumes[index];
          return SizedBox(
            width: width,
            child: NexusFocusable(
              onTap: () => onOpen(resume),
              borderRadius: const BorderRadius.all(Radius.circular(14)),
              semanticLabel: 'Continuar ${resume.asset.name}',
              builder: (context, focused, hovered) => AnimatedContainer(
                duration: const Duration(milliseconds: 170),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.9),
                  borderRadius: const BorderRadius.all(Radius.circular(14)),
                  border: Border.all(
                    color: focused
                        ? AppColors.cyan
                        : hovered
                        ? AppColors.cyan.withValues(alpha: 0.45)
                        : AppColors.border,
                    width: focused ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                      child: SizedBox(
                        width: phone ? 68 : 80,
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: _PosterImage(
                            url: resume.asset.poster,
                            name: resume.asset.name,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            resume.asset.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                          if (resume.episode != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              resume.episode!.number > 0
                                  ? 'Episodio ${resume.episode!.number}'
                                  : resume.episode!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                          const Spacer(),
                          Row(
                            children: [
                              Icon(
                                Icons.play_circle_fill_rounded,
                                size: 15,
                                color: AppColors.cyan,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  resume.durationMs > 0
                                      ? '${_timeLabel(resume.position)} de ${_timeLabel(resume.duration)}'
                                      : '${_timeLabel(resume.position)} reproducidos',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (resume.durationMs > 0) ...[
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: const BorderRadius.all(
                                Radius.circular(99),
                              ),
                              child: LinearProgressIndicator(
                                value: resume.progress,
                                minHeight: 3,
                                backgroundColor: AppColors.border,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

String _timeLabel(Duration value) {
  final seconds = value.inSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final rest = seconds % 60;
  final mm = minutes.toString().padLeft(hours > 0 ? 2 : 1, '0');
  final ss = rest.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

// ------------------------------------------------------------------- cabecera

class _Header extends StatelessWidget {
  const _Header({
    required this.layout,
    required this.kind,
    required this.onKind,
    required this.onRefresh,
    required this.loading,
    required this.subtitle,
    required this.search,
    required this.onQuery,
  });

  final AppLayout layout;
  final WiwyVodKind kind;
  final ValueChanged<WiwyVodKind> onKind;
  final VoidCallback onRefresh;
  final bool loading;
  final String subtitle;
  final TextEditingController search;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searchField = ChannelSearchField(
      controller: search,
      onChanged: onQuery,
      hint: 'Buscar películas y series…',
      height: 44,
    );
    final refreshButton = NexusFocusable(
      onTap: onRefresh,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      semanticLabel: 'Actualizar catálogo',
      builder: (context, focused, hovered) => Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          border: Border.all(
            color: focused || hovered ? AppColors.cyan : AppColors.border,
          ),
        ),
        child: loading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh_rounded, size: 20),
      ),
    );
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cine',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textMuted,
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (layout.isPhone) ...[
          Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 10),
              refreshButton,
            ],
          ),
          const SizedBox(height: 12),
          searchField,
        ] else
          Row(
            children: [
              Expanded(child: title),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: SizedBox(width: 320, child: searchField),
              ),
              const SizedBox(width: 10),
              refreshButton,
            ],
          ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            for (final option in WiwyVodKind.values)
              _KindChip(
                label: option.label,
                selected: option == kind,
                onTap: () => onKind(option),
              ),
          ],
        ),
      ],
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NexusFocusable(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(999)),
      focusedScale: 1.05,
      semanticLabel: label,
      builder: (context, focused, hovered) {
        final active = selected || focused || hovered;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.cyan.withValues(alpha: 0.18)
                : AppColors.surface,
            borderRadius: const BorderRadius.all(Radius.circular(999)),
            border: Border.all(
              color: active ? AppColors.cyan : AppColors.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? AppColors.cyan : AppColors.textPrimary,
            ),
          ),
        );
      },
    );
  }
}

// ------------------------------------------------------------------- tarjetas

class _PosterCard extends StatelessWidget {
  const _PosterCard({required this.asset, required this.onTap, this.badge});

  final WiwyVodAsset asset;
  final VoidCallback onTap;

  /// Etiqueta opcional (Películas/Series/Infantil) para los resultados.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return NexusFocusable(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(14)),
      semanticLabel: asset.name,
      builder: (context, focused, hovered) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 170),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.circular(14)),
                border: Border.all(
                  color: focused
                      ? AppColors.cyan
                      : hovered
                      ? AppColors.cyan.withValues(alpha: 0.45)
                      : AppColors.border,
                  width: focused ? 2 : 1,
                ),
                boxShadow: focused
                    ? [
                        BoxShadow(
                          color: AppColors.glow(0.35),
                          blurRadius: 26,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _PosterImage(url: asset.poster, name: asset.name),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Color(0xC0000000)],
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  if (asset.score > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: const BorderRadius.all(
                            Radius.circular(8),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 12,
                              color: Color(0xFFFFC857),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              asset.score.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (badge != null && badge!.isNotEmpty)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.cyan.withValues(alpha: 0.86),
                          borderRadius: const BorderRadius.all(
                            Radius.circular(8),
                          ),
                        ),
                        child: Text(
                          badge!,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.onAccent,
                          ),
                        ),
                      ),
                    ),
                  if (asset.isSeries && asset.episodeCount > 0)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: const BorderRadius.all(
                            Radius.circular(8),
                          ),
                        ),
                        child: Text(
                          '${asset.episodeCount} cap.',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            asset.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _PosterImage extends StatelessWidget {
  const _PosterImage({required this.url, required this.name});

  final String url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: AppColors.surface,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Text(
        name,
        maxLines: 3,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
    );

    if (url.isEmpty) return placeholder;
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => placeholder,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : placeholder,
    );
  }
}

// ---------------------------------------------------------------------- ficha

class VodDetailPage extends StatefulWidget {
  const VodDetailPage({
    super.key,
    required this.layout,
    required this.kind,
    required this.asset,
    required this.source,
    this.initialResume,
    this.autoPlayResume = false,
  });

  final AppLayout layout;
  final WiwyVodKind kind;
  final WiwyVodAsset asset;
  final WiwySource source;

  /// Progreso con el que se abrió la ficha (desde «Continuar viendo»).
  final VodResume? initialResume;

  /// Entra directamente en el reproductor al cargar la ficha.
  final bool autoPlayResume;

  @override
  State<VodDetailPage> createState() => _VodDetailPageState();
}

class _VodDetailPageState extends State<VodDetailPage> {
  final WiwyVodResolver _resolver = WiwyVodResolver();
  WiwyVodDetail? _detail;
  String? _error;
  String? _playError;
  bool _loading = true;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _resolver.close();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final session = await widget.source.ensureSession();
      final detail = await widget.source.vod.detail(
        session,
        widget.kind,
        widget.asset,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
      final resume = widget.initialResume;
      if (widget.autoPlayResume && resume != null) {
        unawaited(_play(resume: resume));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo abrir la ficha ($error).';
        _loading = false;
      });
    }
  }

  Future<void> _play({
    WiwyVodEpisode? episode,
    VodResume? resume,
    bool fromStart = false,
  }) async {
    if (_resolving) return;
    final targetEpisode = episode ?? resume?.episode;
    debugPrint(
      'VOD play: ${widget.asset.name} ep=${targetEpisode?.name ?? '-'}',
    );
    setState(() {
      _resolving = true;
      _playError = null;
    });

    try {
      final media = await _requestPlayback(targetEpisode);
      if (media == null) {
        throw StateError('el portal no devolvió el vídeo');
      }

      final cdns = widget.source.slb?.vodCdns ?? const <WiwyCdn>[];
      final channel = await _resolver.resolve(cdns: cdns, media: media);
      if (!mounted) return;

      if (channel == null) {
        setState(() {
          _playError =
              'El portal no entrega la señal de este título en este momento. '
              'Vuelve a intentarlo en unos minutos.';
          _resolving = false;
        });
        return;
      }

      // Los subtítulos viajan aparte del `.ts`: se piden antes de abrir el
      // reproductor para que aparezcan ya seleccionados.
      final subtitles = await widget.source.vod.subtitles(
        widget.asset,
        episode: targetEpisode,
      );
      if (!mounted) return;

      // El reproductor siempre recibe un registro de progreso: así se guarda
      // la posición incluso la primera vez que se abre un título. Solo se
      // reutiliza el guardado cuando corresponde al mismo episodio.
      final saved = fromStart
          ? null
          : (resume ??
              AppScope.read(context).vodResumeFor(widget.asset.contentId));
      final reusable = saved != null &&
          saved.episode?.contentId == targetEpisode?.contentId;
      final playerResume = reusable
          ? saved
          : VodResume(
              asset: widget.asset,
              episode: targetEpisode,
              kind: widget.kind,
              positionMs: 0,
              durationMs: 0,
              updatedAt: DateTime.now(),
            );

      setState(() => _resolving = false);
      await openChannelPlayer(
        context,
        channel.copyWith(subtitles: subtitles),
        resume: playerResume,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _playError = 'No se pudo preparar la reproducción ($error).';
        _resolving = false;
      });
    }
  }

  /// Pide la media al portal; si el token cacheado ya no sirve, renueva la
  /// sesión y reintenta una vez (el `userToken` guardado puede haber caducado).
  Future<WiwyVodPlayback?> _requestPlayback(WiwyVodEpisode? episode) async {
    final session = await widget.source.ensureSession();
    try {
      return await widget.source.vod.playback(
        session,
        widget.kind,
        widget.asset,
        episode: episode,
      );
    } catch (_) {
      await widget.source.ensureFresh(force: true);
      final renewed = await widget.source.ensureSession();
      return widget.source.vod.playback(
        renewed,
        widget.kind,
        widget.asset,
        episode: episode,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final asset = _detail?.asset ?? widget.asset;
    final layout = widget.layout;
    // Nos suscribimos al estado para que el botón «Continuar» aparezca en
    // cuanto el reproductor guarda el primer punto de reproducción.
    final saved = AppScope.of(context).vodResumeFor(widget.asset.contentId);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.22,
              child: _PosterImage(url: asset.backdrop, name: asset.name),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.background.withValues(alpha: 0.55),
                    AppColors.background.withValues(alpha: 0.96),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                layout.pagePadding,
                16,
                layout.pagePadding,
                40,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BackButton(onTap: () => Navigator.of(context).maybePop()),
                  const SizedBox(height: 18),
                  _body(asset, saved),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(WiwyVodAsset asset, VodResume? saved) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 80),
        child: Center(child: NeonSpinner()),
      );
    }

    final error = _error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 40),
        child: ErrorState(message: error, onRetry: () => unawaited(_load())),
      );
    }

    final detail = _detail!;
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final canContinue = saved != null && saved.positionMs >= 5000;

    final poster = ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      child: SizedBox(
        width: wide ? 240 : 160,
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: _PosterImage(url: asset.poster, name: asset.name),
        ),
      ),
    );

    final genres = _VodScreenState._genresOf(asset);
    final meta = <String>[
      if (detail.year.isNotEmpty) detail.year,
      if (asset.duration.isNotEmpty) asset.duration,
      if (genres.isNotEmpty) genres.join(' · '),
    ];

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          asset.name,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (asset.score > 0)
              _Pill(
                icon: Icons.star_rounded,
                label: asset.score.toStringAsFixed(1),
                color: const Color(0xFFFFC857),
              ),
            for (final item in meta) _Pill(label: item),
            if (detail.audio.isNotEmpty)
              _Pill(icon: Icons.volume_up_rounded, label: detail.audio),
          ],
        ),
        const SizedBox(height: 18),
        if (detail.synopsis.isNotEmpty)
          Text(
            detail.synopsis,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppColors.textMuted,
            ),
          ),
        if (detail.actors.isNotEmpty) ...[
          const SizedBox(height: 14),
          _InfoLine(label: 'Reparto', value: detail.actors),
        ],
        if (detail.director.isNotEmpty) ...[
          const SizedBox(height: 8),
          _InfoLine(label: 'Dirección', value: detail.director),
        ],
        if (_playError != null) ...[
          const SizedBox(height: 14),
          Text(
            _playError!,
            style: const TextStyle(color: AppColors.danger, fontSize: 13),
          ),
        ],
        const SizedBox(height: 20),
        if (canContinue) ...[
          _ContinueButton(
            enabled: !_resolving,
            busy: _resolving,
            label: saved.episode != null
                ? (saved.episode!.number > 0
                    ? 'Continuar episodio ${saved.episode!.number}'
                    : 'Continuar ${saved.episode!.name}')
                : 'Continuar reproduciendo',
            detail: saved.durationMs > 0
                ? '${_timeLabel(saved.position)} de ${_timeLabel(saved.duration)}'
                : '${_timeLabel(saved.position)} reproducidos',
            onTap: () => unawaited(_play(resume: saved)),
          ),
          const SizedBox(height: 12),
        ],
        if (detail.hasEpisodes) ...[
          const Text(
            'Capítulos',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final episode in detail.episodes)
                _EpisodeChip(
                  episode: episode,
                  enabled: !_resolving,
                  onTap: () => unawaited(_play(episode: episode)),
                ),
            ],
          ),
          if (_resolving) ...[
            const SizedBox(height: 18),
            const SizedBox(
              height: 3,
              child: LinearProgressIndicator(minHeight: 3),
            ),
          ],
        ] else if (canContinue)
          _SecondaryButton(
            enabled: !_resolving,
            label: 'Reproducir desde el principio',
            onTap: () => unawaited(_play(fromStart: true)),
          )
        else
          _PlayButton(
            enabled: !_resolving,
            busy: _resolving,
            onTap: () => unawaited(_play()),
          ),
      ],
    );

    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: poster),
          const SizedBox(height: 20),
          info,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        poster,
        const SizedBox(width: 28),
        Expanded(child: info),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NexusFocusable(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(10)),
      focusedScale: 1.05,
      semanticLabel: 'Volver',
      builder: (context, focused, hovered) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.8),
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          border: Border.all(
            color: focused ? AppColors.cyan : AppColors.border,
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back_rounded, size: 18),
            SizedBox(width: 6),
            Text('Volver', style: TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NexusFocusable(
      onTap: onTap,
      enabled: enabled,
      borderRadius: const BorderRadius.all(Radius.circular(999)),
      semanticLabel: 'Reproducir',
      builder: (context, focused, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.cyan,
          borderRadius: const BorderRadius.all(Radius.circular(999)),
          boxShadow: focused
              ? [
                  BoxShadow(
                    color: AppColors.glow(0.5),
                    blurRadius: 24,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.onAccent,
                ),
              )
            else
              Icon(
                Icons.play_arrow_rounded,
                size: 20,
                color: AppColors.onAccent,
              ),
            const SizedBox(width: 8),
            Text(
              busy ? 'Preparando…' : 'Reproducir',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.onAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({
    required this.enabled,
    required this.busy,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final bool enabled;
  final bool busy;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NexusFocusable(
      onTap: onTap,
      enabled: enabled,
      borderRadius: const BorderRadius.all(Radius.circular(999)),
      semanticLabel: label,
      builder: (context, focused, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.cyan,
          borderRadius: const BorderRadius.all(Radius.circular(999)),
          boxShadow: focused
              ? [
                  BoxShadow(
                    color: AppColors.glow(0.5),
                    blurRadius: 24,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.onAccent,
                ),
              )
            else
              Icon(
                Icons.play_arrow_rounded,
                size: 22,
                color: AppColors.onAccent,
              ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onAccent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.enabled,
    required this.label,
    required this.onTap,
  });

  final bool enabled;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NexusFocusable(
      onTap: onTap,
      enabled: enabled,
      borderRadius: const BorderRadius.all(Radius.circular(999)),
      semanticLabel: label,
      builder: (context, focused, hovered) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.all(Radius.circular(999)),
          border: Border.all(
            color: focused || hovered ? AppColors.cyan : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.replay_rounded, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeChip extends StatelessWidget {
  const _EpisodeChip({
    required this.episode,
    required this.enabled,
    required this.onTap,
  });

  final WiwyVodEpisode episode;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final number = episode.number > 0 ? episode.number : 0;
    return NexusFocusable(
      onTap: onTap,
      enabled: enabled,
      borderRadius: const BorderRadius.all(Radius.circular(10)),
      focusedScale: 1.04,
      semanticLabel: 'Capítulo $number',
      builder: (context, focused, hovered) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: focused
              ? AppColors.cyan.withValues(alpha: 0.16)
              : AppColors.surface,
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          border: Border.all(
            color: focused ? AppColors.cyan : AppColors.border,
          ),
        ),
        child: Text(
          number > 0 ? 'Cap. $number' : episode.name,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: focused ? AppColors.cyan : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({this.icon, required this.label, this.color});

  final IconData? icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color ?? AppColors.textMuted),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color ?? AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              fontSize: 13,
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
