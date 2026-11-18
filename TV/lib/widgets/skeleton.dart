import 'package:flutter/material.dart';

import '../core/app_layout.dart';
import '../core/app_theme.dart';

/// Contenedor con animación de brillo para pantallas de carga.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final slide = (_controller.value * 3) - 1.5;
            return LinearGradient(
              colors: const [
                AppColors.surfaceElevated,
                Color(0xFF2A2B32),
                AppColors.surfaceElevated,
              ],
              stops: const [0.25, 0.5, 0.75],
              transform: _SlidingGradientTransform(slide),
            ).createShader(bounds);
          },
          child: child,
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform(this.slide);

  final double slide;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slide, 0, 0);
  }
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height, this.radius = 8});

  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class ChannelCardSkeleton extends StatelessWidget {
  const ChannelCardSkeleton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Container(
        height: 76,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const SkeletonBox(width: 56, height: 56, radius: 12),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(width: 160, height: 13),
                  SizedBox(height: 8),
                  SkeletonBox(width: 90, height: 10),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: SkeletonBox(width: 92, height: 52, radius: 10),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(width: 130, height: 13),
                SizedBox(height: 8),
                SkeletonBox(width: 76, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChannelGridSkeleton extends StatelessWidget {
  const ChannelGridSkeleton({
    super.key,
    required this.layout,
    this.count = 12,
    this.padding = EdgeInsets.zero,
  });

  final AppLayout layout;
  final int count;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (layout.isPhone) {
      return Shimmer(
        child: ListView.separated(
          padding: padding,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: count,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, _) => const ChannelCardSkeleton(compact: true),
        ),
      );
    }

    return Shimmer(
      child: GridView.builder(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: layout.gridMaxExtent,
          childAspectRatio: layout.gridAspectRatio,
          mainAxisSpacing: layout.gridSpacing,
          crossAxisSpacing: layout.gridSpacing,
        ),
        itemCount: count,
        itemBuilder: (_, _) => const ChannelCardSkeleton(),
      ),
    );
  }
}

/// Esqueleto de la pantalla de inicio mientras se descarga la lista.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key, required this.layout});

  final AppLayout layout;

  @override
  Widget build(BuildContext context) {
    final horizontal = layout.pagePadding;
    return Shimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBox(width: 220, height: 22),
            const SizedBox(height: 18),
            SkeletonBox(
              width: double.infinity,
              height: layout.isPhone ? 190 : 240,
              radius: 24,
            ),
            const SizedBox(height: 28),
            const SkeletonBox(width: 180, height: 20),
            const SizedBox(height: 14),
            SizedBox(
              height: 44,
              child: Row(
                children: List.generate(5, (index) {
                  return const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: SkeletonBox(width: 96, height: 44, radius: 22),
                  );
                }),
              ),
            ),
            const SizedBox(height: 28),
            if (layout.isPhone)
              Column(
                children: List.generate(5, (index) {
                  return const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: ChannelCardSkeleton(compact: true),
                  );
                }),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: layout.gridMaxExtent,
                  childAspectRatio: layout.gridAspectRatio,
                  mainAxisSpacing: layout.gridSpacing,
                  crossAxisSpacing: layout.gridSpacing,
                ),
                itemCount: 8,
                itemBuilder: (_, _) => const ChannelCardSkeleton(),
              ),
          ],
        ),
      ),
    );
  }
}
