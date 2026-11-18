import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/app_theme.dart';
import 'nav_destinations.dart';
import 'nexus_focusable.dart';

/// Rail vertical del escritorio, inspirado en el mock: botones circulares,
/// el activo en blanco y Ajustes fijado abajo. Se expande al pasar el ratón
/// para mostrar las etiquetas.
class DesktopSidebar extends StatefulWidget {
  const DesktopSidebar({
    super.key,
    required this.index,
    required this.onSelect,
  });

  final int index;
  final ValueChanged<int> onSelect;

  @override
  State<DesktopSidebar> createState() => _DesktopSidebarState();
}

class _DesktopSidebarState extends State<DesktopSidebar> {
  bool _expanded = false;

  void _goBack(BuildContext context) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final width = _expanded ? 228.0 : 76.0;
    final settingsIndex = appDestinations.length - 1;

    return MouseRegion(
      onEnter: (_) => setState(() => _expanded = true),
      onExit: (_) => setState(() => _expanded = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: width,
        decoration: const BoxDecoration(
          color: Color(0xFF101114),
          border: Border(right: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          right: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
            child: Column(
              crossAxisAlignment: _expanded
                  ? CrossAxisAlignment.stretch
                  : CrossAxisAlignment.center,
              children: [
                _RailItem(
                  icon: Icons.arrow_back_ios_new_rounded,
                  label: 'Atrás',
                  expanded: _expanded,
                  onTap: () => _goBack(context),
                ),
                const SizedBox(height: 18),
                for (var i = 0; i < appDestinations.length - 1; i++) ...[
                  _RailItem(
                    destination: appDestinations[i],
                    selected: widget.index == i,
                    expanded: _expanded,
                    badge: i == 1 && app.favoritesCount > 0
                        ? '${app.favoritesCount}'
                        : null,
                    onTap: () => widget.onSelect(i),
                  ),
                  const SizedBox(height: 6),
                ],
                const Spacer(),
                _RailItem(
                  icon: Icons.sync_rounded,
                  label: app.isRefreshing ? 'Actualizando…' : 'Actualizar',
                  expanded: _expanded,
                  showSpinner: app.isRefreshing,
                  onTap: app.isRefreshing
                      ? null
                      : () => unawaited(app.refresh(silent: true)),
                ),
                const SizedBox(height: 6),
                _RailItem(
                  destination: appDestinations[settingsIndex],
                  selected: widget.index == settingsIndex,
                  expanded: _expanded,
                  onTap: () => widget.onSelect(settingsIndex),
                ),
                if (_expanded) ...[
                  const SizedBox(height: 14),
                  const Center(
                    child: Text(
                      'v1.0.0 · media_kit',
                      style: TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 9,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    this.destination,
    this.icon,
    this.label,
    required this.expanded,
    required this.onTap,
    this.selected = false,
    this.badge,
    this.showSpinner = false,
  });

  final AppDestination? destination;
  final IconData? icon;
  final String? label;
  final bool expanded;
  final bool selected;
  final String? badge;
  final bool showSpinner;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final resolvedIcon = destination == null
        ? icon
        : (selected ? destination!.selectedIcon : destination!.icon);
    final text = label ?? destination?.label ?? '';
    final enabled = onTap != null;

    final circle = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: expanded ? double.infinity : 48,
      height: 48,
      padding: EdgeInsets.symmetric(horizontal: expanded ? 13 : 0),
      child: Row(
        mainAxisAlignment: expanded
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          if (showSpinner)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textMuted,
              ),
            )
          else
            Icon(
              resolvedIcon,
              size: 21,
              color: selected
                  ? Colors.white
                  : enabled
                  ? AppColors.textMuted
                  : AppColors.textFaint,
            ),
          if (expanded) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : enabled
                      ? AppColors.textPrimary
                      : AppColors.textFaint,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ],
      ),
    );

    return Tooltip(
      message: text,
      waitDuration: const Duration(milliseconds: 500),
      child: NexusFocusable(
        onTap: onTap ?? () {},
        enabled: enabled,
        borderRadius: BorderRadius.circular(99),
        focusedScale: 1.03,
        semanticLabel: text,
        builder: (context, focused, hovered) {
          final decorated = AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.cyan
                  : (hovered
                        ? AppColors.cyan.withValues(alpha: 0.15)
                        : Colors.transparent),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: focused && !selected
                    ? AppColors.cyan.withValues(alpha: 0.4)
                    : Colors.transparent,
                width: 1.4,
              ),
            ),
            child: circle,
          );

          if (expanded || badge == null) return decorated;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              decorated,
              Positioned(
                top: -1,
                right: -1,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: const Color(0xFF101114),
                      width: 1.5,
                    ),
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      color: AppColors.onAccent,
                      fontSize: 7.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
