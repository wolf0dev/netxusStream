import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'core/app_scope.dart';
import 'core/app_theme.dart';
import 'screens/root_shell.dart';

class NexusStreamApp extends StatefulWidget {
  const NexusStreamApp({super.key});

  @override
  State<NexusStreamApp> createState() => _NexusStreamAppState();
}

class _NexusStreamAppState extends State<NexusStreamApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // En TV y móvil el temporizador de renovación se detiene mientras la app
    // está en segundo plano: al volver se comprueba la caducidad y, si hace
    // falta, se renuevan las credenciales sin que el usuario haga nada.
    unawaited(AppScope.read(context).ensureFreshStream());
  }

  @override
  Widget build(BuildContext context) {
    // Depende del estado global para reconstruir el tema al cambiar el acento.
    AppScope.of(context);
    return MaterialApp(
      title: 'NexusStream',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themed(),
      scrollBehavior: const _AppScrollBehavior(),
      builder: (context, child) {
        return MediaQuery.withClampedTextScaling(
          minScaleFactor: 0.85,
          maxScaleFactor: 1.2,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const RootShell(),
    );
  }
}

class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}
