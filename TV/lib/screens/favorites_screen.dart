import 'package:flutter/material.dart';

import '../core/app_layout.dart';
import '../core/app_scope.dart';
import '../core/formatters.dart';
import '../widgets/channel_collection.dart';
import '../widgets/feedback.dart';
import 'player_screen.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({
    super.key,
    required this.layout,
    required this.onOpenChannels,
  });

  final AppLayout layout;
  final VoidCallback onOpenChannels;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final favorites = app.favoriteChannels;
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
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Favoritos',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      favorites.isEmpty
                          ? 'Tu colección personal de canales'
                          : '${formatNumber(favorites.length)} canales guardados',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (favorites.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _confirmClear(context),
                  icon: const Icon(Icons.delete_sweep_rounded, size: 17),
                  label: const Text('Borrar todos'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFFDA4AF),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: favorites.isEmpty
                ? EmptyState(
                    icon: Icons.favorite_border_rounded,
                    title: 'Aún no tienes favoritos',
                    message:
                        'Toca el corazón en cualquier canal para guardarlo aquí '
                        'y acceder a él al instante.',
                    actionLabel: 'Explorar canales',
                    onAction: onOpenChannels,
                  )
                : ChannelCollection(
                    channels: favorites,
                    layout: layout,
                    isFavorite: app.isFavorite,
                    padding: const EdgeInsets.only(bottom: 20),
                    onOpen: (channel) => openChannelPlayer(context, channel),
                    onToggleFavorite: (channel) {
                      app.toggleFavorite(channel);
                      showAppSnackBar(
                        context,
                        '${channel.name} eliminado de favoritos',
                        icon: Icons.heart_broken_rounded,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final app = AppScope.read(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('¿Borrar todos los favoritos?'),
          content: const Text(
            'Esta acción quitará todos los canales guardados. No se puede '
            'deshacer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE11D48),
              ),
              child: const Text('Borrar todos'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      app.clearFavorites();
      if (context.mounted) {
        showAppSnackBar(
          context,
          'Favoritos eliminados',
          icon: Icons.delete_outline_rounded,
        );
      }
    }
  }
}
