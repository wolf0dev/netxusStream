import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Distribución visual activa de la aplicación.
enum AppLayout { phone, tv, desktop }

/// Preferencia del usuario para forzar una distribución concreta.
enum UiModePreference { auto, phone, tv, desktop }

extension UiModePreferenceX on UiModePreference {
  String get label => switch (this) {
    UiModePreference.auto => 'Automático',
    UiModePreference.phone => 'Teléfono',
    UiModePreference.tv => 'Android TV',
    UiModePreference.desktop => 'Escritorio',
  };

  IconData get icon => switch (this) {
    UiModePreference.auto => Icons.auto_awesome_rounded,
    UiModePreference.phone => Icons.smartphone_rounded,
    UiModePreference.tv => Icons.tv_rounded,
    UiModePreference.desktop => Icons.desktop_windows_rounded,
  };
}

extension AppLayoutX on AppLayout {
  bool get isPhone => this == AppLayout.phone;
  bool get isTv => this == AppLayout.tv;
  bool get isDesktop => this == AppLayout.desktop;
  bool get isWide => this != AppLayout.phone;

  String get label => switch (this) {
    AppLayout.phone => 'Teléfono',
    AppLayout.tv => 'Android TV',
    AppLayout.desktop => 'Escritorio',
  };

  double get pagePadding => switch (this) {
    AppLayout.phone => 16,
    AppLayout.tv => 36,
    AppLayout.desktop => 32,
  };

  /// Número de canales mostrados en la vista previa del inicio.
  int get previewCount => switch (this) {
    AppLayout.phone => 6,
    AppLayout.tv => 15,
    AppLayout.desktop => 12,
  };

  double get gridMaxExtent => switch (this) {
    AppLayout.phone => 220,
    AppLayout.tv => 310,
    AppLayout.desktop => 280,
  };

  double get gridAspectRatio => switch (this) {
    AppLayout.phone => 1.15,
    AppLayout.tv => 1.42,
    AppLayout.desktop => 1.35,
  };

  double get gridSpacing => switch (this) {
    AppLayout.phone => 12,
    AppLayout.tv => 20,
    AppLayout.desktop => 16,
  };

  double get sectionGap => switch (this) {
    AppLayout.phone => 26,
    AppLayout.tv => 34,
    AppLayout.desktop => 32,
  };
}

/// `true` en Windows, macOS y Linux (sin contar web).
bool get isDesktopPlatform {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;
}

/// Resuelve la distribución a partir de la preferencia y el dispositivo.
AppLayout resolveLayout({
  required UiModePreference preference,
  required bool isTvDevice,
}) {
  return switch (preference) {
    UiModePreference.phone => AppLayout.phone,
    UiModePreference.tv => AppLayout.tv,
    UiModePreference.desktop => AppLayout.desktop,
    UiModePreference.auto => _autoLayout(isTvDevice),
  };
}

AppLayout _autoLayout(bool isTvDevice) {
  if (isDesktopPlatform) return AppLayout.desktop;
  if (isTvDevice) return AppLayout.tv;
  return AppLayout.phone;
}

/// Ancho máximo del contenido en pantallas grandes.
const double kContentMaxWidth = 1680;
