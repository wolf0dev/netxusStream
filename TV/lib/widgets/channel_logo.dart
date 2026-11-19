import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/channel.dart';

/// Logo remoto con placeholder degradado y manejo de errores.
class ChannelLogo extends StatelessWidget {
  const ChannelLogo({
    super.key,
    required this.channel,
    this.width,
    this.height,
    this.size,
    this.radius = 12,
    this.fit = BoxFit.contain,
  }) : assert(size == null || (width == null && height == null));

  final Channel channel;
  final double? width;
  final double? height;
  final double? size;
  final double radius;
  final BoxFit fit;

  static const List<List<Color>> _palettes = [
    [Color(0xFF0E7490), Color(0xFF1D4ED8)],
    [Color(0xFF6D28D9), Color(0xFF2563EB)],
    [Color(0xFF0F766E), Color(0xFF0891B2)],
    [Color(0xFF7C3AED), Color(0xFFBE185D)],
    [Color(0xFF1E40AF), Color(0xFF4338CA)],
    [Color(0xFF9D174D), Color(0xFF6D28D9)],
  ];

  @override
  Widget build(BuildContext context) {
    final resolvedWidth = size ?? width;
    final resolvedHeight = size ?? height;
    final content = _buildContent(resolvedWidth, resolvedHeight);

    if (resolvedWidth == null && resolvedHeight == null) {
      return SizedBox.expand(child: content);
    }

    return SizedBox(
      width: resolvedWidth,
      height: resolvedHeight,
      child: content,
    );
  }

  Widget _buildContent(double? resolvedWidth, double? resolvedHeight) {
    final placeholder = _LogoFallback(channel: channel, palette: _palette);
    if (!channel.hasLogo) return placeholder;

    // Los logos del portal suelen ser mucho más grandes que la tarjeta. En TV
    // (con cientos de canales) decodificarlos a tamaño completo llena la
    // memoria y provoca tirones. Forzamos una decodificación miniaturizada.
    int? cacheDimension(double? value) {
      if (value == null) return null;
      return value.clamp(16.0, 256.0).round();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        channel.logo,
        fit: fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        cacheWidth: cacheDimension(resolvedWidth ?? resolvedHeight ?? size) ?? 128,
        cacheHeight:
            cacheDimension(resolvedHeight ?? resolvedWidth ?? size) ?? 128,
        errorBuilder: (_, _, _) => placeholder,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return placeholder;
        },
      ),
    );
  }

  List<Color> get _palette {
    final seed = channel.name.codeUnits.fold<int>(
      0,
      (total, code) => total + code,
    );
    return _palettes[seed % _palettes.length];
  }
}

class _LogoFallback extends StatelessWidget {
  const _LogoFallback({required this.channel, required this.palette});

  final Channel channel;
  final List<Color> palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [
            palette.first.withValues(alpha: 0.34),
            palette.last.withValues(alpha: 0.22),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Text(
              channel.initials,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 18,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
