import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// Banner horizontal oficial con el logotipo y el nombre de la marca.
class BrandBanner extends StatelessWidget {
  const BrandBanner({
    super.key,
    this.height = 110,
    this.alignment = Alignment.centerLeft,
  });

  final double height;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/banner.png',
      height: height,
      fit: BoxFit.contain,
      alignment: alignment,
      filterQuality: FilterQuality.high,
      semanticLabel: 'NexusStream, IPTV Player',
    );
  }
}

/// Isotipo cuadrado de la aplicación.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40, this.radius = 11});

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        'assets/icono.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        semanticLabel: 'NexusStream',
      ),
    );
  }
}

/// Texto con el degradado de la marca.
class GradientText extends StatelessWidget {
  const GradientText(
    this.text, {
    super.key,
    required this.style,
    this.gradient,
    this.maxLines = 1,
  });

  final String text;
  final TextStyle style;
  final Gradient? gradient;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final shader = gradient ?? AppColors.brandGradientHorizontal;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: shader.createShader,
      child: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style.copyWith(color: Colors.white),
      ),
    );
  }
}

/// Isotipo + nombre, usado en la barra lateral y la navegación de TV.
class BrandLockup extends StatelessWidget {
  const BrandLockup({
    super.key,
    this.markSize = 40,
    this.showTagline = true,
    this.textSize = 15,
  });

  final double markSize;
  final bool showTagline;
  final double textSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: markSize),
        const SizedBox(width: 10),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GradientText(
              'NEXUSSTREAM',
              style: TextStyle(
                fontSize: textSize,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                height: 1.1,
              ),
            ),
            if (showTagline) ...[
              const SizedBox(height: 2),
              Text(
                'IPTV PLAYER',
                style: TextStyle(
                  fontSize: textSize * 0.55,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2.2,
                  color: AppColors.textMuted,
                  height: 1.1,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
