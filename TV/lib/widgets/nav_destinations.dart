import 'package:flutter/material.dart';

class AppDestination {
  const AppDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Destinos de la app. La antigua pestaña «Inicio» pasa a ser «TV» en vivo,
/// y el orden sigue el mock: TV, Favoritos, Cine y Ajustes.
const List<AppDestination> appDestinations = [
  AppDestination(
    label: 'TV',
    icon: Icons.live_tv_outlined,
    selectedIcon: Icons.live_tv_rounded,
  ),
  AppDestination(
    label: 'Favoritos',
    icon: Icons.star_border_rounded,
    selectedIcon: Icons.star_rounded,
  ),
  AppDestination(
    label: 'Cine',
    icon: Icons.movie_outlined,
    selectedIcon: Icons.movie_rounded,
  ),
  AppDestination(
    label: 'Ajustes',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
  ),
];
