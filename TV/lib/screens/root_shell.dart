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

  void _select(int index) {
    if (index == _index) return;
    debugPrint('Sección: $index');
    setState(() => _index = index);
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

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
            _select(0),
        SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
            _select(1),
        SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
            _select(2),
        SingleActivator(LogicalKeyboardKey.digit4, control: true): () =>
            _select(3),
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
    );
  }
}
