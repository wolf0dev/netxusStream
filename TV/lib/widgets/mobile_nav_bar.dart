import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import 'nav_destinations.dart';
import 'nexus_focusable.dart';

/// Barra inferior táctil para teléfonos Android.
class MobileNavBar extends StatelessWidget {
  const MobileNavBar({
    super.key,
    required this.index,
    required this.onSelect,
    this.favoritesCount = 0,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final int favoritesCount;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.navy.withValues(alpha: 0.96),
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            children: [
              for (var i = 0; i < appDestinations.length; i++)
                Expanded(
                  child: _MobileItem(
                    destination: appDestinations[i],
                    selected: index == i,
                    badge: i == 1 && favoritesCount > 0
                        ? favoritesCount > 9
                              ? '9+'
                              : '$favoritesCount'
                        : null,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileItem extends StatelessWidget {
  const _MobileItem({
    required this.destination,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final AppDestination destination;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return NexusFocusable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      focusedScale: 1.02,
      semanticLabel: destination.label,
      builder: (context, focused, hovered) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
          decoration: BoxDecoration(
            color: focused ? Colors.white.withValues(alpha: 0.04) : null,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: focused ? AppColors.cyan : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      gradient: selected
                          ? AppColors.brandGradientHorizontal
                          : null,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Icon(
                      selected ? destination.selectedIcon : destination.icon,
                      size: 20,
                      color: selected
                          ? AppColors.onAccent
                          : AppColors.textMuted,
                    ),
                  ),
                  if (badge != null)
                    Positioned(
                      top: -3,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.violet,
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: AppColors.navy, width: 1.5),
                        ),
                        child: Text(
                          badge!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                destination.label,
                style: TextStyle(
                  color: selected ? AppColors.cyan : AppColors.textFaint,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
