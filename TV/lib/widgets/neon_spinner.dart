import 'package:flutter/material.dart';

import 'brand.dart';

/// Indicador circular con degradado cian → violeta y halo neón.
///
/// Se usa en el reproductor mientras el canal carga o se reconecta. Es una
/// versión estilizada de [CircularProgressIndicator] con los colores de la
/// marca, sin depender de los controles por defecto de `media_kit`.
class NeonSpinner extends StatefulWidget {
  const NeonSpinner({super.key, this.size = 56, this.strokeWidth = 3.4});

  final double size;
  final double strokeWidth;

  @override
  State<NeonSpinner> createState() => _NeonSpinnerState();
}

class _NeonSpinnerState extends State<NeonSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Halo suave detrás del anillo.
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.14),
                  blurRadius: widget.size * 0.55,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          RotationTransition(
            turns: _controller,
            child: ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => const SweepGradient(
                colors: [
                  Colors.transparent,
                  Color(0xFFF2F3F6),
                  Color(0xFF8B8F99),
                  Colors.transparent,
                ],
                stops: [0.0, 0.32, 0.72, 1.0],
              ).createShader(bounds),
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: CircularProgressIndicator(
                  value: 0.78,
                  strokeWidth: widget.strokeWidth,
                  strokeCap: StrokeCap.round,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          // Isotipo de la marca en el centro.
          BrandMark(size: widget.size * 0.36, radius: widget.size * 0.1),
        ],
      ),
    );
  }
}
