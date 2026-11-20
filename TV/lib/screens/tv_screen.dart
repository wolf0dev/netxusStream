import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/app_layout.dart';
import '../core/app_scope.dart';
import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../core/player_tuning.dart';
import '../models/channel.dart';
import '../state/app_state.dart';
import '../widgets/category_filter.dart';
import '../widgets/channel_logo.dart';
import '../widgets/feedback.dart';
import '../widgets/neon_spinner.dart';
import '../widgets/nexus_focusable.dart';
import '../widgets/search_field.dart';
import 'player_screen.dart';

/// Pantalla principal de TV en vivo, inspirada en el mock de referencia:
/// lista de canales a la izquierda y vista previa en directo a la derecha.
class TvScreen extends StatefulWidget {
  const TvScreen({
    super.key,
    required this.layout,
    required this.active,
    this.onOpenSettings,
  });

  final AppLayout layout;

  /// `false` cuando otra sección está visible. Se usa para pausar el vídeo
  /// incrustado y no dejar audio de fondo.
  final bool active;

  final VoidCallback? onOpenSettings;

  @override
  State<TvScreen> createState() => _TvScreenState();
}

class _TvScreenState extends State<TvScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'TvSearch');
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  Player? _player;
  VideoController? _controller;
  Channel? _preview;

  bool _loading = false;
  bool _playing = false;
  bool _buffering = false;
  bool _muted = true;
  bool _autoStarted = false;
  bool _wasPlaying = false;
  String? _error;
  int _openRequest = 0;
  int _retryCount = 0;
  Timer? _retryTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    if (!_searchFocus.hasFocus && _searchController.text != app.query) {
      _searchController.value = TextEditingValue(
        text: app.query,
        selection: TextSelection.collapsed(offset: app.query.length),
      );
    }
  }

  @override
  void didUpdateWidget(covariant TvScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;

    if (!widget.active) {
      _wasPlaying = _playing;
      unawaited(_player?.pause());
    } else if (_wasPlaying && _preview != null) {
      unawaited(_player?.play());
    }
  }

  @override
  void dispose() {
    _openRequest++;
    _retryTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_player?.dispose());
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // Reproducción ---------------------------------------------------------------

  void _ensurePlayer() {
    if (_player != null) return;

    final player = Player(
      configuration: PlayerTuning.playerConfiguration(isTv: true),
    );
    final controller = VideoController(
      player,
      configuration: PlayerTuning.videoConfiguration(isTv: true),
    );
    _player = player;
    _controller = controller;
    unawaited(PlayerTuning.applyNativeTuning(player, isTv: true));
    unawaited(player.setVolume(_muted ? 0 : 100));

    _subscriptions.add(
      player.stream.playing.listen((value) {
        if (!mounted) return;
        if (value) _retryCount = 0;
        setState(() => _playing = value);
      }),
    );
    _subscriptions.add(
      player.stream.buffering.listen((value) {
        if (!mounted) return;
        setState(() => _buffering = value);
      }),
    );
    _subscriptions.add(
      player.stream.error.listen((error) {
        if (!mounted) return;
        debugPrint('Error de la vista previa: $error');
        _handleFailure('No se pudo reproducir esta señal.');
      }),
    );
  }

  /// Un fallo de red no debe romper la vista previa: se reintenta en silencio
  /// un par de veces (renovando credenciales del portal) antes de avisar.
  void _handleFailure(String message) {
    if (!mounted) return;
    _retryTimer?.cancel();
    final channel = _preview;
    if (channel != null && _retryCount < 2) {
      _retryCount++;
      setState(() {
        _loading = true;
        _buffering = false;
        _error = null;
      });
      _retryTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        unawaited(_previewChannel(channel, force: true, resetRetries: false));
      });
      return;
    }

    setState(() {
      _error = message;
      _loading = false;
      _buffering = false;
    });
  }

  Future<void> _previewChannel(
    Channel channel, {
    bool force = false,
    bool autoplay = true,
    bool resetRetries = true,
  }) async {
    if (!force && _preview?.url == channel.url && _player != null) {
      if (autoplay) unawaited(_player!.play());
      return;
    }

    _retryTimer?.cancel();
    if (resetRetries) _retryCount = 0;

    final app = AppScope.read(context);
    _ensurePlayer();
    app.rememberChannel(channel);

    final request = ++_openRequest;
    setState(() {
      _preview = channel;
      _loading = true;
      _buffering = false;
      _error = null;
    });

    // Portal Wiwy: los tokens de directo caducan; renovarlos antes de abrir.
    if (app.useWiwy) {
      try {
        await app.ensureFreshStream().timeout(const Duration(seconds: 15));
      } catch (error) {
        debugPrint('No se pudieron renovar las credenciales: $error');
      }
      if (!mounted || request != _openRequest) return;
    }

    try {
      await _player!.open(
        Media(channel.url, httpHeaders: channel.httpHeaders),
        play: autoplay && widget.active,
      );
    } catch (error) {
      if (!mounted || request != _openRequest) return;
      debugPrint('No se pudo abrir ${channel.name}: $error');
      _handleFailure('No se pudo abrir ${channel.name}.');
      return;
    }

    if (!mounted || request != _openRequest) return;
    _retryCount = 0;
    setState(() => _loading = false);
  }

  Future<void> _togglePlay() async {
    final player = _player;
    final channel = _preview;
    if (player == null || channel == null) return;
    if (_playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    unawaited(_player?.setVolume(_muted ? 0 : 100));
  }

  void _retryPreview() {
    final channel = _preview;
    if (channel == null) return;
    unawaited(_previewChannel(channel, force: true));
  }

  Future<void> _openFullScreen(Channel channel) async {
    final wasPlaying = _playing;
    await _player?.pause();
    if (!mounted) return;
    await openChannelPlayer(context, channel);
    if (mounted && wasPlaying && widget.active) {
      unawaited(_player?.play());
    }
  }

  /// Auto-selecciona el último canal visto (o el primero de la lista) para que
  /// el panel derecho nunca arranque vacío.
  void _maybeAutoStart(AppState app) {
    if (_autoStarted || !widget.active || _preview != null) return;
    final first =
        app.lastChannel ??
        (app.visibleChannels.isNotEmpty ? app.visibleChannels.first : null);
    if (first == null) return;

    _autoStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.active || _preview != null) return;
      unawaited(_previewChannel(first));
    });
  }

  // Interfaz -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    _maybeAutoStart(app);

    final content = widget.layout.isPhone
        ? _buildPhone(context, app)
        : _buildWide(context, app);

    if (!widget.layout.isTv) return content;

    // Atajo de teclado para TV/PC: F abre el canal en pantalla completa.
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyF): () {
          final channel = _preview;
          if (channel != null) unawaited(_openFullScreen(channel));
        },
      },
      child: content,
    );
  }

  Widget _buildPhone(BuildContext context, AppState app) {
    final layout = widget.layout;
    final padding = layout.pagePadding;

    return Padding(
      padding: EdgeInsets.fromLTRB(padding, 14, padding, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'En Vivo TV',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${formatNumber(app.channels.length)} canales · '
                      '${formatNumber(app.categories.length)} categorías',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              _RefreshIcon(
                refreshing: app.isRefreshing,
                onRefresh: () => unawaited(app.refresh(silent: true)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ChannelSearchField(
            controller: _searchController,
            focusNode: _searchFocus,
            onChanged: app.setQuery,
            hint: 'Buscar canales…',
            height: 46,
          ),
          const SizedBox(height: 10),
          CategoryFilter(
            categories: app.categories,
            selected: app.selectedGroup,
            totalChannels: app.channels.length,
            onSelected: app.setGroup,
            layout: layout,
          ),
          const SizedBox(height: 6),
          Expanded(child: _buildChannelList(context, app, phone: true)),
        ],
      ),
    );
  }

  Widget _buildWide(BuildContext context, AppState app) {
    final layout = widget.layout;
    final padding = layout.isTv ? 24.0 : 22.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(padding, padding, padding, 18),
      child: Row(
        children: [
          Expanded(
            flex: 43,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              decoration: BoxDecoration(
                color: AppColors.navy.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'En Vivo TV',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              app.query.trim().isEmpty
                                  ? '${formatNumber(app.visibleChannels.length)} canales en directo'
                                  : '${formatNumber(app.visibleChannels.length)} resultados',
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _RefreshIcon(
                        refreshing: app.isRefreshing,
                        onRefresh: () => unawaited(app.refresh(silent: true)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  CategoryFilter(
                    categories: app.categories,
                    selected: app.selectedGroup,
                    totalChannels: app.channels.length,
                    onSelected: app.setGroup,
                    layout: layout,
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: _buildChannelList(context, app, phone: false),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            flex: 57,
            child: _LivePreview(
              channel: _preview,
              controller: _controller,
              loading: _loading,
              buffering: _buffering,
              playing: _playing,
              muted: _muted,
              error: _error,
              isTv: layout.isTv,
              searchController: _searchController,
              searchFocus: _searchFocus,
              onSearchChanged: app.setQuery,
              onTogglePlay: () => unawaited(_togglePlay()),
              onToggleMute: _toggleMute,
              onRetry: _retryPreview,
              onOpenFullScreen: _preview == null
                  ? null
                  : () => unawaited(_openFullScreen(_preview!)),
              onOpenSettings: widget.onOpenSettings,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelList(
    BuildContext context,
    AppState app, {
    required bool phone,
  }) {
    if (app.isInitialLoading && !app.hasChannels) {
      return const Center(child: NeonSpinner(size: 46));
    }

    if (!app.hasChannels) {
      return ErrorState(
        message: app.errorMessage ?? 'No hay canales disponibles ahora mismo.',
        onRetry: () => unawaited(app.refresh()),
      );
    }

    if (app.visibleChannels.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Sin resultados',
        message: 'No encontramos canales con esos filtros.',
        actionLabel: 'Limpiar filtros',
        onAction: () {
          _searchController.clear();
          app.clearFilters();
        },
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 12, top: 2),
      itemCount: app.visibleChannels.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final channel = app.visibleChannels[index];
        return _TvChannelTile(
          channel: channel,
          selected: !phone && _preview?.url == channel.url,
          isFavorite: app.isFavorite(channel),
          viewers: _viewersLabel(channel),
          quality: _qualityLabel(channel),
          is4k: _is4k(channel),
          onTap: () {
            if (phone) {
              unawaited(_openFullScreen(channel));
            } else if (_preview?.url == channel.url) {
              // Segundo OK sobre el canal ya sintonizado: pantalla completa.
              unawaited(_openFullScreen(channel));
            } else {
              unawaited(_previewChannel(channel));
            }
          },
          onToggleFavorite: () {
            final added = app.toggleFavorite(channel);
            showAppSnackBar(
              context,
              added
                  ? '${channel.name} añadido a favoritos'
                  : '${channel.name} eliminado de favoritos',
              icon: added ? Icons.star_rounded : Icons.star_border_rounded,
            );
          },
        );
      },
    );
  }
}

// Helpers de presentación -------------------------------------------------------

int _seedFor(Channel channel) {
  var hash = 7;
  for (final code in channel.url.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return hash;
}

String _viewersLabel(Channel channel) {
  final value = 0.4 + (_seedFor(channel) % 94) / 10.0;
  return '+${value.toStringAsFixed(1)}M Vistas';
}

bool _is4k(Channel channel) {
  final name = channel.name.toUpperCase();
  return name.contains('4K') || name.contains('UHD');
}

String _qualityLabel(Channel channel) => _is4k(channel) ? '4K' : 'HD';

class _TvChannelTile extends StatelessWidget {
  const _TvChannelTile({
    required this.channel,
    required this.selected,
    required this.isFavorite,
    required this.viewers,
    required this.quality,
    required this.is4k,
    required this.onTap,
    required this.onToggleFavorite,
  });

  final Channel channel;
  final bool selected;
  final bool isFavorite;
  final String viewers;
  final String quality;
  final bool is4k;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return NexusFocusable(
      onTap: onTap,
      onFocusChange: (focused) {
        if (!focused) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
          );
        });
      },
      borderRadius: BorderRadius.circular(16),
      focusedScale: 1.012,
      semanticLabel: channel.name,
      builder: (context, focused, hovered) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? Colors.white.withValues(alpha: 0.10)
                : hovered
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.028),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? Colors.white.withValues(alpha: 0.65)
                  : focused
                  ? Colors.white.withValues(alpha: 0.4)
                  : AppColors.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: ChannelLogo(
                  channel: channel,
                  size: 46,
                  radius: 12,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? Colors.white : AppColors.textPrimary,
                        fontSize: 13.5,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            viewers,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _QualityTag(label: quality),
                        if (is4k) ...[
                          const SizedBox(width: 4),
                          const _QualityTag(label: 'HD'),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: onToggleFavorite,
                tooltip: isFavorite
                    ? 'Quitar de favoritos'
                    : 'Añadir a favoritos',
                icon: Icon(
                  isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 19,
                  color: isFavorite ? AppColors.warning : AppColors.textFaint,
                ),
                style: IconButton.styleFrom(
                  minimumSize: const Size(34, 34),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QualityTag extends StatelessWidget {
  const _QualityTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _LivePreview extends StatelessWidget {
  const _LivePreview({
    required this.channel,
    required this.controller,
    required this.loading,
    required this.buffering,
    required this.playing,
    required this.muted,
    required this.error,
    required this.isTv,
    required this.searchController,
    required this.searchFocus,
    required this.onSearchChanged,
    required this.onTogglePlay,
    required this.onToggleMute,
    required this.onRetry,
    required this.onOpenFullScreen,
    required this.onOpenSettings,
  });

  final Channel? channel;
  final VideoController? controller;
  final bool loading;
  final bool buffering;
  final bool playing;
  final bool muted;
  final String? error;
  final bool isTv;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleMute;
  final VoidCallback onRetry;
  final VoidCallback? onOpenFullScreen;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final preview = channel;
    final showVideo = preview != null && controller != null;
    // Igual que en el reproductor a pantalla completa: si ya hay imagen, los
    // eventos de `buffering` de libmpv no deben dejar el spinner permanente.
    final busy = loading || (buffering && !playing);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Colors.black),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (showVideo)
              Video(
                controller: controller!,
                controls: NoVideoControls,
                fit: BoxFit.cover,
                fill: Colors.black,
              )
            else
              _PreviewBackdrop(channel: preview),

            // Degradados para que los controles se lean sobre la imagen.
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 150,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
            const Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 260,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xE6000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),

            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _PreviewTopBar(
                      searchController: searchController,
                      searchFocus: searchFocus,
                      onSearchChanged: onSearchChanged,
                      onOpenSettings: onOpenSettings,
                    ),
                    const Spacer(),
                    _PreviewBottomBar(
                      channel: preview,
                      playing: playing,
                      muted: muted,
                      isTv: isTv,
                      onTogglePlay: onTogglePlay,
                      onToggleMute: onToggleMute,
                      onOpenFullScreen: onOpenFullScreen,
                    ),
                  ],
                ),
              ),
            ),

            if (busy) const Center(child: NeonSpinner(size: 52)),

            if (error != null)
              Center(
                child: _PreviewError(message: error!, onRetry: onRetry),
              )
            else if (!busy && !playing && preview != null)
              Center(
                child: _RoundIconButton(
                  icon: Icons.play_arrow_rounded,
                  size: 68,
                  iconSize: 38,
                  filled: true,
                  onTap: onTogglePlay,
                  tooltip: 'Reproducir',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PreviewBackdrop extends StatelessWidget {
  const _PreviewBackdrop({this.channel});

  final Channel? channel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.heroGradient),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (channel != null)
              Opacity(
                opacity: 0.9,
                child: ChannelLogo(
                  channel: channel!,
                  size: 108,
                  radius: 20,
                  fit: BoxFit.contain,
                ),
              )
            else
              Icon(
                Icons.live_tv_rounded,
                size: 68,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            const SizedBox(height: 18),
            Text(
              channel == null
                  ? 'Selecciona un canal'
                  : 'Preparando ${channel!.name}…',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewTopBar extends StatelessWidget {
  const _PreviewTopBar({
    required this.searchController,
    required this.searchFocus,
    required this.onSearchChanged,
    required this.onOpenSettings,
  });

  final TextEditingController searchController;
  final FocusNode searchFocus;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _Clock(),
        const Spacer(),
        SizedBox(
          width: 210,
          child: ChannelSearchField(
            controller: searchController,
            focusNode: searchFocus,
            onChanged: onSearchChanged,
            hint: 'Buscar canales…',
            height: 40,
          ),
        ),
        const SizedBox(width: 10),
        _AvatarButton(onTap: onOpenSettings),
      ],
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock();

  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static const _days = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
  static const _months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];

  @override
  Widget build(BuildContext context) {
    final hour = _now.hour.toString().padLeft(2, '0');
    final minute = _now.minute.toString().padLeft(2, '0');
    final date =
        '${_days[_now.weekday - 1]} ${_now.day} ${_months[_now.month - 1]}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$hour:$minute',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            height: 1,
            shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          date,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _AvatarButton extends StatelessWidget {
  const _AvatarButton({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Ajustes',
      child: NexusFocusable(
        onTap: () => onTap?.call(),
        enabled: onTap != null,
        borderRadius: BorderRadius.circular(999),
        focusedScale: 1.1,
        semanticLabel: 'Ajustes',
        builder: (context, focused, hovered) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF3B82F6),
              border: Border.all(
                color: focused
                    ? AppColors.accent
                    : Colors.white.withValues(alpha: hovered ? 0.8 : 0.55),
                width: focused ? 2.4 : 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: focused
                      ? AppColors.accent.withValues(alpha: 0.5)
                      : Colors.black.withValues(alpha: 0.3),
                  blurRadius: focused ? 16 : 10,
                ),
              ],
            ),
            child: const Icon(
              Icons.person_rounded,
              color: Colors.white,
              size: 22,
            ),
          );
        },
      ),
    );
  }
}

class _PreviewBottomBar extends StatelessWidget {
  const _PreviewBottomBar({
    required this.channel,
    required this.playing,
    required this.muted,
    required this.isTv,
    required this.onTogglePlay,
    required this.onToggleMute,
    required this.onOpenFullScreen,
  });

  final Channel? channel;
  final bool playing;
  final bool muted;
  final bool isTv;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleMute;
  final VoidCallback? onOpenFullScreen;

  @override
  Widget build(BuildContext context) {
    final preview = channel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            return Row(
              children: [
                const _LivePill(),
                if (preview != null) ...[
                  const SizedBox(width: 8),
                  _QualityTag(label: _qualityLabel(preview)),
                ],
                const Spacer(),
                _RoundIconButton(
                  icon: playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  onTap: onTogglePlay,
                  tooltip: playing ? 'Pausar' : 'Reproducir',
                ),
                const SizedBox(width: 8),
                if (muted)
                  _SoundPill(onTap: onToggleMute)
                else
                  _RoundIconButton(
                    icon: Icons.volume_up_rounded,
                    onTap: onToggleMute,
                    tooltip: 'Silenciar',
                  ),
                const SizedBox(width: 8),
                if (compact)
                  _RoundIconButton(
                    icon: Icons.open_in_full_rounded,
                    onTap: onOpenFullScreen,
                    tooltip: 'Pantalla completa',
                  )
                else
                  _FullscreenPill(onTap: onOpenFullScreen),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        Text(
          preview == null ? 'Vista previa' : 'Reproduciendo',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.62),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          preview?.name ?? 'Selecciona un canal para empezar',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        if (isTv && preview != null) ...[
          const SizedBox(height: 5),
          Row(
            children: [
              Icon(
                Icons.gamepad_rounded,
                size: 12,
                color: Colors.white.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Pulsa OK otra vez en el canal para verlo a pantalla completa',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 11),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: preview == null ? 0 : null,
                  minHeight: 3,
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'En Vivo',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Botón grande y enfocable para abrir el canal en pantalla completa con el
/// control remoto. El texto se oculta en paneles estrechos.
class _FullscreenPill extends StatelessWidget {
  const _FullscreenPill({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Pantalla completa',
      child: NexusFocusable(
        onTap: () => onTap?.call(),
        enabled: onTap != null,
        borderRadius: BorderRadius.circular(999),
        focusedScale: 1.05,
        semanticLabel: 'Pantalla completa',
        builder: (context, focused, hovered) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              gradient: focused ? AppColors.brandGradientHorizontal : null,
              color: focused
                  ? null
                  : Colors.white.withValues(alpha: hovered ? 0.26 : 0.16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: focused
                    ? AppColors.accent
                    : Colors.white.withValues(alpha: 0.22),
                width: focused ? 1.6 : 1,
              ),
              boxShadow: focused
                  ? [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.4),
                        blurRadius: 16,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.open_in_full_rounded,
                  size: 17,
                  color: focused ? AppColors.onAccent : Colors.white,
                ),
                const SizedBox(width: 7),
                Text(
                  'Pantalla completa',
                  style: TextStyle(
                    color: focused ? AppColors.onAccent : Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFFF87171),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'EN VIVO',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}

class _SoundPill extends StatelessWidget {
  const _SoundPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Activar sonido',
      child: NexusFocusable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        focusedScale: 1.06,
        semanticLabel: 'Activar sonido',
        builder: (context, focused, hovered) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: focused
                  ? AppColors.accent
                  : Colors.white.withValues(alpha: hovered ? 0.9 : 1),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: focused
                    ? AppColors.accent
                    : Colors.white.withValues(alpha: 0.3),
                width: focused ? 2 : 1,
              ),
              boxShadow: focused
                  ? [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.45),
                        blurRadius: 14,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.volume_off_rounded,
                  size: 16,
                  color: AppColors.onAccent,
                ),
                const SizedBox(width: 6),
                Text(
                  'Activar sonido',
                  style: TextStyle(
                    color: AppColors.onAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.size = 34,
    this.iconSize = 19,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final double size;
  final double iconSize;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: NexusFocusable(
        onTap: () => onTap?.call(),
        enabled: onTap != null,
        borderRadius: BorderRadius.circular(999),
        focusedScale: 1.12,
        semanticLabel: tooltip,
        builder: (context, focused, hovered) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled
                  ? (focused
                        ? AppColors.accent
                        : Colors.white.withValues(alpha: hovered ? 0.9 : 1))
                  : Colors.white.withValues(
                      alpha: focused || hovered ? 0.28 : 0.14,
                    ),
              border: Border.all(
                color: focused
                    ? AppColors.accent
                    : Colors.white.withValues(alpha: filled ? 0.0 : 0.18),
                width: focused ? 2 : 1,
              ),
              boxShadow: focused
                  ? [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.4),
                        blurRadius: 14,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              size: iconSize,
              color: filled ? AppColors.onAccent : Colors.white,
            ),
          );
        },
      ),
    );
  }
}

class _PreviewError extends StatelessWidget {
  const _PreviewError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.signal_cellular_connected_no_internet_0_bar_rounded,
            color: AppColors.warning,
            size: 30,
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Reintentar'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RefreshIcon extends StatelessWidget {
  const _RefreshIcon({required this.refreshing, required this.onRefresh});

  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: refreshing ? 'Actualizando…' : 'Actualizar lista',
      onPressed: refreshing ? null : onRefresh,
      icon: refreshing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync_rounded, size: 20),
    );
  }
}
