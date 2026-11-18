import 'dart:io';

import 'package:flutter/material.dart';

import '../core/app_layout.dart';
import '../core/app_scope.dart';
import '../core/app_theme.dart';

/// Fondo global: imagen propia del usuario o wallpaper de temporada, con
/// resplandores sutiles encima.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final custom = app.customWallpaperPath;
    final asset = app.seasonalTheme.asset(phone: app.layout.isPhone);

    Widget wallpaper() {
      if (custom != null) {
        return Image.file(
          File(custom),
          key: ValueKey('file:$custom'),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          opacity: const AlwaysStoppedAnimation<double>(0.62),
          errorBuilder: (_, _, _) => asset == null
              ? const SizedBox.shrink()
              : Image.asset(
                  asset,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  opacity: const AlwaysStoppedAnimation<double>(0.62),
                ),
        );
      }
      return Image.asset(
        asset!,
        key: ValueKey(asset),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        opacity: const AlwaysStoppedAnimation<double>(0.62),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppColors.background),
        if (custom != null || asset != null) ...[
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: wallpaper(),
            ),
          ),
          // Oscurece el fondo lo justo para que la interfaz siga legible.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x4D141519),
                    Color(0x9E141519),
                    Color(0xE6141519),
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
        ],
        Positioned(
          top: -260,
          left: -180,
          child: _Glow(color: Colors.white.withValues(alpha: 0.035), size: 560),
        ),
        Positioned(
          bottom: -300,
          right: -160,
          child: _Glow(color: Colors.white.withValues(alpha: 0.03), size: 640),
        ),
        child,
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            stops: const [0, 1],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta translúcida reutilizable.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderRadius = 16,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor ?? AppColors.border),
      ),
      child: child,
    );
  }
}
