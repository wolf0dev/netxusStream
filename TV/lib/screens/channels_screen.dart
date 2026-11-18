import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_layout.dart';
import '../core/app_scope.dart';
import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../widgets/category_filter.dart';
import '../widgets/channel_collection.dart';
import '../widgets/feedback.dart';
import '../widgets/search_field.dart';
import '../widgets/skeleton.dart';
import 'player_screen.dart';

class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key, required this.layout});

  final AppLayout layout;

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'ChannelsSearch');

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
    final padding = layout.pagePadding;

    final header = _ChannelsHeader(
      layout: layout,
      controller: _searchController,
      focusNode: _searchFocus,
      onSearchChanged: app.setQuery,
      onRefresh: () => unawaited(app.refresh(silent: true)),
      refreshing: app.isRefreshing,
      total: app.channels.length,
      categories: app.categories.length,
    );

    if (app.isInitialLoading && !app.hasChannels) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          padding,
          layout.isPhone ? 14 : 24,
          padding,
          0,
        ),
        child: Column(
          children: [
            header,
            const SizedBox(height: 18),
            Expanded(child: ChannelGridSkeleton(layout: widget.layout)),
          ],
        ),
      );
    }

    if (!app.hasChannels) {
      return Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          children: [
            header,
            const SizedBox(height: 16),
            Expanded(
              child: ErrorState(
                message:
                    app.errorMessage ??
                    'No hay canales disponibles en este momento.',
                onRetry: () => unawaited(app.refresh()),
              ),
            ),
          ],
        ),
      );
    }

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
          header,
          if (app.isRefreshing) ...[
            const SizedBox(height: 10),
            const ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(2)),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          ],
          if (app.hasError) ...[
            const SizedBox(height: 12),
            InlineErrorBanner(
              message: app.errorMessage!,
              onRetry: () => unawaited(app.refresh(silent: true)),
              onDismiss: app.dismissError,
            ),
          ],
          const SizedBox(height: 12),
          CategoryFilter(
            categories: app.categories,
            selected: app.selectedGroup,
            totalChannels: app.channels.length,
            onSelected: app.setGroup,
            layout: layout,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  app.query.trim().isEmpty && app.selectedGroup == null
                      ? '${formatNumber(app.visibleChannels.length)} canales en vivo'
                      : '${formatNumber(app.visibleChannels.length)} resultados'
                            '${app.selectedGroup != null ? ' · ${app.selectedGroup}' : ''}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (app.query.isNotEmpty || app.selectedGroup != null)
                TextButton.icon(
                  onPressed: () {
                    _searchController.clear();
                    app.clearFilters();
                  },
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 15),
                  label: const Text('Limpiar filtros'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: app.visibleChannels.isEmpty
                ? EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Sin resultados',
                    message:
                        'No encontramos canales con esos filtros. Prueba con '
                        'otra categoría u otro término de búsqueda.',
                    actionLabel: 'Limpiar filtros',
                    onAction: () {
                      _searchController.clear();
                      app.clearFilters();
                    },
                  )
                : ChannelCollection(
                    channels: app.visibleChannels,
                    layout: layout,
                    isFavorite: app.isFavorite,
                    padding: const EdgeInsets.only(bottom: 20),
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
          ),
        ],
      ),
    );
  }
}

class _ChannelsHeader extends StatelessWidget {
  const _ChannelsHeader({
    required this.layout,
    required this.controller,
    required this.focusNode,
    required this.onSearchChanged,
    required this.onRefresh,
    required this.refreshing,
    required this.total,
    required this.categories,
  });

  final AppLayout layout;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onRefresh;
  final bool refreshing;
  final int total;
  final int categories;

  @override
  Widget build(BuildContext context) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Canales', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 3),
        Text(
          '${formatNumber(total)} señales · ${formatNumber(categories)} categorías',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );

    final refreshIcon = IconButton(
      tooltip: refreshing ? 'Actualizando…' : 'Actualizar lista',
      onPressed: refreshing ? null : onRefresh,
      icon: refreshing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.sync_rounded, size: 21),
    );

    if (layout.isPhone) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: title),
              IconButton(
                tooltip: 'Buscar',
                onPressed: () => focusNode.requestFocus(),
                icon: const Icon(Icons.search_rounded, size: 21),
              ),
              refreshIcon,
            ],
          ),
          const SizedBox(height: 10),
          ChannelSearchField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onSearchChanged,
            height: 46,
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: title),
        SizedBox(
          width: layout.isTv ? 330 : 340,
          child: ChannelSearchField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onSearchChanged,
            height: 44,
          ),
        ),
        const SizedBox(width: 8),
        refreshIcon,
      ],
    );
  }
}
