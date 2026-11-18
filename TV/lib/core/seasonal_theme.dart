import 'package:flutter/material.dart';

/// Fondos de temporada incluidos en `assets/temas`.
///
/// La app elige uno automáticamente según la fecha, pero el usuario puede
/// fijarlo desde Ajustes (o desactivarlo).
enum SeasonalTheme {
  auto('Automático', Icons.auto_awesome_rounded, null),
  newYear('Año Nuevo', Icons.celebration_rounded, 'an'),
  carnival('Carnaval', Icons.festival_rounded, 'cr'),
  halloween('Halloween', Icons.dark_mode_rounded, 'hlw'),
  christmas('Navidad', Icons.ac_unit_rounded, 'nv'),
  none('Sin tema', Icons.hide_image_rounded, null);

  const SeasonalTheme(this.label, this.icon, this._assetBase);

  final String label;
  final IconData icon;
  final String? _assetBase;

  /// Ruta del wallpaper para el formato indicado. Las imágenes `-v` son
  /// exclusivas de teléfono; el resto sirven para PC y TV.
  String? asset({required bool phone}) {
    final base = _assetBase;
    if (base == null) return null;
    return 'assets/temas/$base${phone ? '_v' : ''}.jpg';
  }

  /// Temporada activa según el calendario.
  static SeasonalTheme forDate(DateTime date) {
    final month = date.month;
    final day = date.day;

    // Navidad: todo diciembre hasta el día 25.
    if (month == 12 && day <= 25) return christmas;
    // Año Nuevo: del 26 de diciembre al 10 de enero.
    if ((month == 12 && day >= 26) || (month == 1 && day <= 10)) {
      return newYear;
    }
    // Carnaval: febrero y la primera quincena de marzo.
    if (month == 2 || (month == 3 && day <= 15)) return carnival;
    // Halloween / Día de Muertos: octubre y los primeros días de noviembre.
    if (month == 10 || (month == 11 && day <= 2)) return halloween;

    return none;
  }

  /// Resuelve la preferencia guardada contra la fecha actual.
  static SeasonalTheme resolve(SeasonalTheme preference, DateTime date) {
    return preference == auto ? forDate(date) : preference;
  }
}
