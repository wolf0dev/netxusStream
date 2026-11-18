import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/app_theme.dart';
import '../core/formatters.dart';
import 'brand.dart';
import 'nav_destinations.dart';
import 'nexus_focusable.dart';

/// Navegación horizontal optimizada para D-pad de Android TV.
class TvNavBar extends StatelessWidget {
  const TvNavBar({super.key, required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Container(
      height: 80,
      decoration: const BoxDecoration(
        color: Color(0xCC1B1C21),
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showStatus = constraints.maxWidth > 1080;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              children: [
                const BrandLockup(markSize: 34, textSize: 13.5),
                SizedBox(width: constraints.maxWidth > 1280 ? 48 : 28),
                for (var i = 0; i < appDestinations.length; i++) ...[
                  _TvNavItem(
                    destination: appDestinations[i],
                    selected: index == i,
                    autofocus: i == index && index == 0,
                    badge: i == 1 && app.favoritesCount > 0
                        ? '${app.favoritesCount}'
                        : null,
                    onTap: () => onSelect(i),
                  ),
                  const SizedBox(width: 8),
                ],
                const Spacer(),
                if (showStatus)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: app.hasError
                                ? AppColors.warning
                                : AppColors.success,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          '${formatNumber(app.channels.length)} canales',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          width: 1,
                          height: 12,
                          color: AppColors.border,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${formatNumber(app.categories.length)} cat.',
                          style: const TextStyle(
                            color: AppColors.textFaint,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TvNavItem extends StatelessWidget {
  const _TvNavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
    required this.autofocus,
    this.badge,
  });

  final AppDestination destination;
  final bool selected;
  final VoidCallback onTap;
  final bool autofocus;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return NexusFocusable(
      onTap: onTap,
      autofocus: autofocus,
      borderRadius: BorderRadius.circular(12),
      focusedScale: 1.06,
      semanticLabel: destination.label,
      builder: (context, focused, hovered) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.cyan
                : (hovered ? Colors.white.withValues(alpha: 0.06) : null),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: focused && !selected
                  ? Colors.white.withValues(alpha: 0.4)
                  : Colors.transparent,
              width: 1.4,
            ),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                size: 19,
                color: selected ? AppColors.onAccent : AppColors.textMuted,
              ),
              const SizedBox(width: 8),
              Text(
                destination.label,
                style: TextStyle(
                  color: selected ? AppColors.onAccent : AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.black.withValues(alpha: 0.14)
                        : Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      color: selected ? AppColors.onAccent : Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
