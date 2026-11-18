import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/app_scope.dart';
import 'core/app_theme.dart';
import 'core/device_profile.dart';
import 'services/proxy_service.dart';
import 'state/app_state.dart';
import 'wiwy/wiwy_source.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  MediaKit.ensureInitialized();
  // Antes de crear cualquier cliente HTTP: si la VPN/proxy está activada en
  // Ajustes, el portal y las imágenes ya salen por ella desde el arranque.
  await ProxySettings.instance.load();

  await _configureDesktopWindow();
  _configureSystemChrome();

  final isTvDevice = await DeviceProfile.isAndroidTv();
  final state = AppState(
    isTvDevice: isTvDevice,
    wiwy: await _createWiwySource(),
  );

  runApp(AppScope(state: state, child: const NexusStreamApp()));

  // La interfaz se muestra de inmediato con la caché; la descarga continúa en
  // segundo plano.
  unawaited(state.bootstrap());
}

/// Fuente del portal WiwyXuper: guarda la caché donde la app tiene permiso de
/// escritura en todas las plataformas (Android TV, Windows, macOS, Linux).
Future<WiwySource> _createWiwySource() async {
  try {
    final directory = await getApplicationSupportDirectory();
    return WiwySource(store: FileWiwyStore(directory.path), logger: debugPrint);
  } catch (error) {
    debugPrint('Error al crear el directorio del servidor, usando memoria: $error');
    // Fallback a memoria si falla el almacenamiento en disco
    return WiwySource(store: MemoryWiwyStore(), logger: debugPrint);
  }
}

Future<void> _configureDesktopWindow() async {
  if (kIsWeb || !(Platform.isWindows || Platform.isLinux)) return;
  try {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1200, 700),
      minimumSize: Size(960, 600),
      center: true,
      title: 'NexusStream',
      backgroundColor: AppColors.background,
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  } catch (error) {
    debugPrint('No se pudo configurar la ventana de escritorio: $error');
  }
}

void _configureSystemChrome() {
  if (kIsWeb || !Platform.isAndroid) return;
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );
}
