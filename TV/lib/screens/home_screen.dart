import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_layout.dart';
import '../core/app_scope.dart';
import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../models/channel.dart';
import '../state/app_state.dart';
import '../widgets/brand.dart';
import '../widgets/category_filter.dart';
import '../widgets/channel_collection.dart';
import '../widgets/feedback.dart';
import '../widgets/nexus_focusable.dart';
import '../widgets/search_field.dart';
import '../widgets/skeleton.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.layout,
    required this.onOpenChannels,
    required this.onOpenFavorites,
  });

  final AppLayout layout;
  final VoidCallback onOpenChannels;
  final VoidCallback onOpenFavorites;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'HomeSearch');

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
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final layout = widget.layout;

    if (app.isInitialLoading && !app.hasChannels) {
      return HomeSkeleton(layout: layout);
    }

    if (!app.hasChannels) {
      return ErrorState(
        message:
            app.errorMessage ??
            'La lista de canales está vacía. Comprueba tu conexión.',
        onRetry: () => unawaited(app.refresh()),
      );
    }

    final searchResults = app.query.trim().isNotEmpty;
    final previewLimit = searchResults ? 30 : layout.previewCount;
    final preview = app.visibleChannels.take(previewLimit).toList();

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        layout.pagePadding,
        layout.isPhone ? 14 : 24,
        layout.pagePadding,
        28,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(
                app: app,
                layout: layout,
                controller: _searchController,
                searchFocus: _searchFocus,
                onSearchChanged: app.setQuery,
                onOpenChannels: widget.onOpenChannels,
              ),
              if (layout.isPhone) ...[
                const SizedBox(height: 12),
                ChannelSearchField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onChanged: app.setQuery,
                ),
              ],
              if (app.hasError) ...[
                const SizedBox(height: 14),
                InlineErrorBanner(
                  message: app.errorMessage!,
                  onRetry: () => unawaited(app.refresh(silent: true)),
                  onDismiss: app.dismissError,
                ),
              ],
              if (!searchResults) ...[
                SizedBox(height: layout.isPhone ? 16 : 32),
                _PrimeHero(
                  app: app,
                  layout: layout,
                  onExplore: widget.onOpenChannels,
                  onFavorites: widget.onOpenFavorites,
                ),
                if (app.lastChannel != null) ...[
                  SizedBox(height: layout.sectionGap),
                  _ContinueWatchingSection(
                    channel: app.lastChannel!,
                    layout: layout,
                    onTap: () => openChannelPlayer(context, app.lastChannel!),
                  ),
                ],
                if (app.featuredChannels.isNotEmpty) ...[
                  SizedBox(height: layout.sectionGap),
                  _FeaturedSection(
                    title: 'En vivo ahora',
                    channels: app.featuredChannels.take(12).toList(),
                    layout: layout,
                    onTap: (channel) => openChannelPlayer(context, channel),
                  ),
                ],
              ] else ...[
                const SizedBox(height: 18),
                Text(
                  'Resultados de búsqueda',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatNumber(app.visibleChannels.length)} coincidencias '
                  'para “${app.query.trim()}”',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              SizedBox(height: layout.sectionGap),
              SectionHeader(
                title: 'Categorías',
                subtitle:
                    '${formatNumber(app.categories.length)} grupos disponibles',
                actionLabel: layout.isTv ? null : 'Todos los canales',
                onAction: widget.onOpenChannels,
              ),
              const SizedBox(height: 10),
              CategoryFilter(
                categories: app.categories,
                selected: app.selectedGroup,
                totalChannels: app.channels.length,
                onSelected: app.setGroup,
                layout: layout,
              ),
              SizedBox(height: layout.sectionGap),
              SectionHeader(
                title: searchResults
                    ? 'Canales encontrados'
                    : 'Explora canales',
                subtitle: searchResults
                    ? 'Selecciona un canal para reproducirlo'
                    : '${formatNumber(app.channels.length)} señales en vivo · '
                          '${formatNumber(app.categories.length)} categorías',
                actionLabel: 'Ver todos',
                onAction: widget.onOpenChannels,
              ),
              const SizedBox(height: 14),
              if (preview.isEmpty)
                EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'Sin canales con estos filtros',
                  message:
                      'Prueba con otra categoría o borra la búsqueda para '
                      'volver a ver toda la lista.',
                  actionLabel: 'Limpiar filtros',
                  onAction: app.clearFilters,
                  secondaryLabel: 'Ver todos los canales',
                  onSecondary: widget.onOpenChannels,
                )
              else
                ChannelCollection(
                  channels: preview,
                  layout: layout,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  isFavorite: app.isFavorite,
                  onOpen: (channel) => openChannelPlayer(context, channel),
                  onToggleFavorite: (channel) {
                    final added = app.toggleFavorite(channel);
                    showAppSnackBar(
                      context,
                      added
                          ? '${channel.name} añadido a favoritos'
                          : '${channel.name} eliminado de favoritos',
                      icon: added
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                    );
                  },
                ),
              const SizedBox(height: 22),
              const Center(
                child: Text(
                  'NexusStream · Datos de IPTV-Org · Reproductor media_kit',
                  style: TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 10.5,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.app,
    required this.layout,
    required this.controller,
    required this.searchFocus,
    required this.onSearchChanged,
    required this.onOpenChannels,
  });

  final AppState app;
  final AppLayout layout;
  final TextEditingController controller;
  final FocusNode searchFocus;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onOpenChannels;

  @override
  Widget build(BuildContext context) {
    final refreshButton = _RefreshIcon(
      refreshing: app.isRefreshing,
      onPressed: () => unawaited(app.refresh(silent: true)),
    );

    if (layout.isPhone) {
      return Row(
        children: [
          const BrandLockup(markSize: 34, showTagline: false, textSize: 13),
          const Spacer(),
          IconButton(
            tooltip: 'Buscar',
            onPressed: () => searchFocus.requestFocus(),
            icon: const Icon(Icons.search_rounded, size: 21),
          ),
          refreshButton,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Inicio', style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 3),
              Text(
                app.isRefreshing
                    ? 'Sincronizando la lista de canales…'
                    : '${formatNumber(app.channels.length)} canales · '
                          '${formatNumber(app.categories.length)} categorías · '
                          '${formatRelative(app.lastUpdated).toLowerCase()}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (layout.isDesktop) ...[
          SizedBox(
            width: 340,
            child: ChannelSearchField(
              controller: controller,
              focusNode: searchFocus,
              onChanged: onSearchChanged,
              height: 44,
            ),
          ),
          const SizedBox(width: 10),
        ],
        if (layout.isTv) ...[
          OutlinedButton.icon(
            onPressed: onOpenChannels,
            icon: const Icon(Icons.search_rounded, size: 17),
            label: const Text('Buscar canales'),
          ),
          const SizedBox(width: 10),
        ],
        refreshButton,
      ],
    );
  }
}

class _RefreshIcon extends StatelessWidget {
  const _RefreshIcon({required this.refreshing, required this.onPressed});

  final bool refreshing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: refreshing ? 'Actualizando…' : 'Actualizar lista',
      onPressed: refreshing ? null : onPressed,
      icon: refreshing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync_rounded, size: 21),
    );
  }
}

class _PrimeHero extends StatelessWidget {
  const _PrimeHero({
    required this.app,
    required this.layout,
    required this.onExplore,
    required this.onFavorites,
  });

  final AppState app;
  final AppLayout layout;
  final VoidCallback onExplore;
  final VoidCallback onFavorites;

  @override
  Widget build(BuildContext context) {
    final isPhone = layout.isPhone;
    final isTv = layout.isTv;

    final heroHeight = isPhone ? 280.0 : (isTv ? 360.0 : 420.0);

    return Container(
      width: double.infinity,
      height: heroHeight,
      decoration: const BoxDecoration(gradient: AppColors.heroGradient),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Fondo de respaldo mientras carga la imagen del hero.
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.07),
                    Colors.white.withValues(alpha: 0.03),
                    AppColors.background,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          // Content
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                layout.pagePadding,
                isPhone ? 60 : 80,
                layout.pagePadding,
                40,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Prime logo
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.cyan,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'prime',
                      style: TextStyle(
                        color: AppColors.onAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'NEXUSSTREAM',
                    style: TextStyle(
                      fontSize: isPhone ? 36 : (isTv ? 48 : 56),
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -1,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.7),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Subtitle
                  Text(
                    'TU SEÑAL, SIN LÍMITES',
                    style: TextStyle(
                      fontSize: isPhone ? 14 : 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.9),
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Stats row
                  Row(
                    children: [
                      _StatBadge(
                        icon: Icons.live_tv_rounded,
                        label: formatNumber(app.channels.length),
                        sublabel: 'canales',
                      ),
                      const SizedBox(width: 12),
                      _StatBadge(
                        icon: Icons.grid_view_rounded,
                        label: formatNumber(app.categories.length),
                        sublabel: 'categorías',
                      ),
                      if (!isPhone) ...[
                        const SizedBox(width: 12),
                        _StatBadge(
                          icon: Icons.favorite_rounded,
                          label: formatNumber(app.favoritesCount),
                          sublabel: 'favoritos',
                          color: const Color(0xFFFB7185),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Buttons
                  Row(
                    children: [
                      _PrimeButton(
                        icon: Icons.play_arrow_rounded,
                        label: 'VER AHORA',
                        isPrimary: true,
                        onPressed: onExplore,
                      ),
                      const SizedBox(width: 12),
                      _PrimeButton(
                        icon: Icons.info_outline_rounded,
                        label: 'SABER MÁS',
                        isPrimary: false,
                        onPressed: onFavorites,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.icon,
    required this.label,
    required this.sublabel,
    this.color,
  });

  final IconData icon;
  final String label;
  final String sublabel;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? AppColors.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                sublabel,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrimeButton extends StatelessWidget {
  const _PrimeButton({
    required this.icon,
    required this.label,
    required this.isPrimary,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool isPrimary;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: isPrimary ? Colors.white : Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withValues(alpha: isPrimary ? 0 : 0.3),
          width: isPrimary ? 0 : 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: isPrimary ? Colors.black : Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: isPrimary ? Colors.black : Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContinueWatchingSection extends StatelessWidget {
  const _ContinueWatchingSection({
    required this.channel,
    required this.layout,
    required this.onTap,
  });

  final Channel channel;
  final AppLayout layout;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
          child: Row(
            children: [
              Text(
                'CONTINUAR VIENDO',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const Spacer(),
              Text(
                '>',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
            itemCount: 1,
            itemBuilder: (context, index) {
              return _ContinueCard(
                channel: channel,
                layout: layout,
                onTap: onTap,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.channel,
    required this.layout,
    required this.onTap,
  });

  final Channel channel;
  final AppLayout layout;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NexusFocusable(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      builder: (context, focused, hovered) {
        final active = focused || hovered;
        return Container(
          width: 240,
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? AppColors.cyan
                  : Colors.white.withValues(alpha: 0.2),
              width: active ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (channel.hasLogo)
                Image.network(
                  channel.logo,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _buildPlaceholder(),
                )
              else
                _buildPlaceholder(),
              // Dark gradient overlay
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.8),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              // Content
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      channel.group,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // Play overlay
              if (active)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.3),
                    child: const Center(
                      child: Icon(
                        Icons.play_circle_outline_rounded,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.surface,
      child: Center(
        child: Text(
          channel.initials,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _FeaturedSection extends StatelessWidget {
  const _FeaturedSection({
    required this.title,
    required this.channels,
    required this.layout,
    required this.onTap,
  });

  final String title;
  final List<Channel> channels;
  final AppLayout layout;
  final ValueChanged<Channel> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
          child: Row(
            children: [
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const Spacer(),
              Text(
                '>',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
            itemCount: channels.length,
            itemBuilder: (context, index) {
              final channel = channels[index];
              return _FeaturedCard(
                channel: channel,
                layout: layout,
                onTap: () => onTap(channel),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({
    required this.channel,
    required this.layout,
    required this.onTap,
  });

  final Channel channel;
  final AppLayout layout;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NexusFocusable(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      builder: (context, focused, hovered) {
        final active = focused || hovered;
        return Container(
          width: 200,
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.2),
              width: active ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (channel.hasLogo)
                Image.network(
                  channel.logo,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _buildPlaceholder(),
                )
              else
                _buildPlaceholder(),
              // Dark gradient overlay
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              // Content
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Text(
                  channel.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Play overlay
              if (active)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.3),
                    child: const Center(
                      child: Icon(
                        Icons.play_circle_outline_rounded,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.surface,
      child: Center(
        child: Text(
          channel.initials,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
