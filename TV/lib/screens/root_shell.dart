import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_layout.dart';
import '../core/app_scope.dart';
import '../widgets/app_background.dart';
import '../widgets/desktop_sidebar.dart';
import '../widgets/mobile_nav_bar.dart';
import '../widgets/tv_nav_bar.dart';
import 'favorites_screen.dart';
import 'settings_screen.dart';
import 'tv_screen.dart';
import 'vod_screen.dart';

/// Contenedor raíz que elige la navegación según el modo de dispositivo.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;
  bool _exitDialogOpen = false;
  DateTime? _lastBackAt;

  void _select(int index) {
    if (index == _index) return;
    debugPrint('Sección: $index');
    setState(() => _index = index);
  }

  /// Atrás del mando/teclado dentro de la ruta raíz.
  ///
  /// Las rutas abiertas encima (detalle de cine, reproductor, diálogos) se
  /// cierran solas y no llegan hasta aquí. En la raíz, Atrás vuelve a Canales
  /// desde cualquier sección; solo estando ya en Canales pregunta si salir.
  void _handleBack() {
    final now = DateTime.now();
    // En Android el mismo Atrás puede llegar como atajo de teclado y como
    // evento del sistema. Ignoramos el segundo dentro de esta ventana.
    if (_lastBackAt != null &&
        now.difference(_lastBackAt!) < const Duration(milliseconds: 400)) {
      return;
    }
    _lastBackAt = now;

    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    if (_index != 0) {
      _select(0);
      return;
    }
    unawaited(_confirmExit());
  }

  Future<void> _confirmExit() async {
    if (_exitDialogOpen || !mounted) return;
    _exitDialogOpen = true;
    try {
      final exit = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('¿Salir de NexusStream?'),
          content: const Text(
            'Pulsa Cancelar para seguir viendo tus canales.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Salir'),
            ),
          ],
        ),
      );
      if (!mounted || exit != true) return;
      SystemNavigator.pop();
    } finally {
      _exitDialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final layout = app.layout;
    final index = _index;

    final pages = <Widget>[
      TvScreen(
        layout: layout,
        active: index == 0,
        onOpenSettings: () => _select(3),
      ),
      FavoritesScreen(layout: layout, onOpenChannels: () => _select(0)),
      VodScreen(layout: layout),
      SettingsScreen(layout: layout),
    ];

    final content = IndexedStack(index: index, children: pages);

    final body = switch (layout) {
      AppLayout.desktop => Row(
        children: [
          DesktopSidebar(index: index, onSelect: _select),
          Expanded(child: content),
        ],
      ),
      AppLayout.tv => FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: SafeArea(
          child: Column(
            children: [
              TvNavBar(index: index, onSelect: _select),
              Expanded(child: content),
            ],
          ),
        ),
      ),
      AppLayout.phone => SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(child: content),
            MobileNavBar(
              index: index,
              onSelect: _select,
              favoritesCount: app.favoritesCount,
            ),
          ],
        ),
      ),
    };

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
              _select(0),
          SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
              _select(1),
          SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
              _select(2),
          SingleActivator(LogicalKeyboardKey.digit4, control: true): () =>
              _select(3),
          const SingleActivator(LogicalKeyboardKey.goBack): _handleBack,
          const SingleActivator(LogicalKeyboardKey.escape): _handleBack,
        },
        child: AppBackground(
          // El Scaffold aporta el Material y el DefaultTextStyle de la app.
          // Sin él, Flutter pinta el estilo de texto de respaldo (subrayado
          // amarillo) en todos los Text que no definen una decoración propia.
          child: Scaffold(
            backgroundColor: Colors.transparent,
            resizeToAvoidBottomInset: false,
            body: body,
          ),
        ),
      ),
    );
  }
}
