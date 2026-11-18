import 'package:flutter/material.dart';

/// Colores de énfasis disponibles para toda la interfaz.
///
/// Se guarda solo el identificador en las preferencias, así que se pueden
/// añadir tonalidades nuevas sin romper las existentes.
class AppAccent {
  const AppAccent(this.id, this.label, this.color);

  final String id;
  final String label;
  final Color color;

  static const white = AppAccent('white', 'Blanco', Color(0xFFFFFFFF));
  static const cyan = AppAccent('cyan', 'Cian', Color(0xFF22D3EE));
  static const sky = AppAccent('sky', 'Celeste', Color(0xFF38BDF8));
  static const blue = AppAccent('blue', 'Azul', Color(0xFF5B8DEF));
  static const violet = AppAccent('violet', 'Violeta', Color(0xFF8B5CF6));
  static const magenta = AppAccent('magenta', 'Magenta', Color(0xFFE879F9));
  static const pink = AppAccent('pink', 'Rosa', Color(0xFFF472B6));
  static const red = AppAccent('red', 'Rojo', Color(0xFFF87171));
  static const orange = AppAccent('orange', 'Naranja', Color(0xFFFB923C));
  static const amber = AppAccent('amber', 'Ámbar', Color(0xFFFBBF24));
  static const green = AppAccent('green', 'Verde', Color(0xFF4ADE80));
  static const teal = AppAccent('teal', 'Turquesa', Color(0xFF2DD4BF));

  static const all = <AppAccent>[
    white,
    cyan,
    sky,
    blue,
    violet,
    magenta,
    pink,
    red,
    orange,
    amber,
    green,
    teal,
  ];

  static AppAccent byId(String? id) {
    return all.firstWhere((accent) => accent.id == id, orElse: () => white);
  }
}
