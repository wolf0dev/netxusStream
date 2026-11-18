import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

/// Gestiona el wallpaper propio del usuario: lo elige con el selector nativo
/// y guarda una copia en la carpeta de soporte de la app para que siga
/// disponible tras reiniciar.
class WallpaperService {
  static const List<String> _extensions = ['jpg', 'jpeg', 'png', 'webp', 'bmp'];

  Future<String?> pickAndStore() async {
    final picked = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Imágenes', extensions: _extensions),
      ],
    );
    if (picked == null) return null;

    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);

    final extension = _extensionOf(picked.path);
    final target = File(
      '${directory.path}${Platform.pathSeparator}custom_wallpaper$extension',
    );

    // Elimina restos de elecciones anteriores con otra extensión.
    for (final ext in _extensions) {
      final stale = File(
        '${directory.path}${Platform.pathSeparator}custom_wallpaper.$ext',
      );
      if (stale.path == target.path) continue;
      try {
        if (await stale.exists()) await stale.delete();
      } catch (_) {
        // Silencioso: no impide guardar la nueva imagen.
      }
    }

    await File(picked.path).copy(target.path);
    return target.path;
  }

  Future<void> remove(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Silencioso: la preferencia se limpia igualmente.
    }
  }

  String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '.jpg';
    final ext = path.substring(dot + 1).toLowerCase();
    return _extensions.contains(ext) ? '.$ext' : '.jpg';
  }
}
