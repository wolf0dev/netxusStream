import 'package:flutter/material.dart';

import '../core/app_layout.dart';
import '../core/app_theme.dart';
import '../models/channel.dart';
import 'nexus_focusable.dart';

/// Selector horizontal de categorías con soporte de control remoto.
class CategoryFilter extends StatelessWidget {
  const CategoryFilter({
    super.key,
    required this.categories,
    required this.selected,
    required this.totalChannels,
    required this.onSelected,
    this.layout = AppLayout.desktop,
  });

  final List<ChannelCategory> categories;
  final String? selected;
  final int totalChannels;
  final ValueChanged<String?> onSelected;
  final AppLayout layout;

  @override
  Widget build(BuildContext context) {
    final height = layout.isTv ? 56.0 : 50.0;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: categories.length + 1,
        separatorBuilder: (_, _) => SizedBox(width: layout.isTv ? 12 : 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _CategoryPill(
              label: 'Todos',
              count: totalChannels,
              selected: selected == null,
              onTap: () => onSelected(null),
              layout: layout,
              icon: Icons.apps_rounded,
            );
          }
          final category = categories[index - 1];
          return _CategoryPill(
            label: category.name,
            count: category.count,
            selected: selected == category.name,
            onTap: () => onSelected(category.name),
            layout: layout,
          );
        },
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    required this.layout,
    this.icon,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final AppLayout layout;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return NexusFocusable(
      onTap: onTap,
      onFocusChange: (focused) {
        if (!focused) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
          );
        });
      },
      borderRadius: BorderRadius.circular(999),
      focusedScale: 1.04,
      semanticLabel: '$label, $count canales',
      builder: (context, focused, hovered) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: layout.isTv ? 18 : 15,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            gradient: selected ? null : AppColors.categoryGradient(label),
            color: selected ? AppColors.cyan : null,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: focused
                  ? Colors.white.withValues(alpha: 0.5)
                  : AppColors.borderStrong,
              width: focused ? 1.6 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 15,
                  color: selected ? AppColors.onAccent : Colors.white,
                ),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppColors.onAccent : Colors.white,
                  fontSize: layout.isTv ? 13.5 : 12.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.black.withValues(alpha: 0.14)
                      : Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  count >= 1000
                      ? '${(count / 1000).toStringAsFixed(1)}k'
                      : '$count',
                  style: TextStyle(
                    color: selected ? AppColors.onAccent : Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
