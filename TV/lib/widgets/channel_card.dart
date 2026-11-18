import 'package:flutter/material.dart';

import '../core/app_layout.dart';
import '../core/app_theme.dart';
import '../models/channel.dart';
import 'channel_logo.dart';
import 'nexus_focusable.dart';

/// Tarjeta de canal. En formato [compact] se usa como fila para teléfonos y en
/// formato grid para escritorio y Android TV.
class ChannelCard extends StatelessWidget {
  const ChannelCard({
    super.key,
    required this.channel,
    required this.isFavorite,
    required this.onTap,
    required this.onToggleFavorite,
    this.compact = false,
    this.layout = AppLayout.desktop,
    this.autofocus = false,
  });

  final Channel channel;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;
  final bool compact;
  final AppLayout layout;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scale = layout.isTv ? 1.05 : (compact ? 1.01 : 1.025);

    return NexusFocusable(
      autofocus: autofocus,
      onTap: onTap,
      onLongPress: onToggleFavorite,
      borderRadius: BorderRadius.circular(compact ? 14 : 16),
      focusedScale: scale,
      semanticLabel:
          '${channel.name}. ${channel.group}. '
          '${isFavorite ? 'Favorito.' : ''}',
      builder: (context, focused, hovered) {
        final active = focused || hovered;
        final decoration = BoxDecoration(
          gradient: compact
              ? null
              : const LinearGradient(
                  colors: [Color(0xFF26272D), Color(0xFF1B1C21)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: compact
              ? (focused ? AppColors.surfaceHighlight : AppColors.surface)
              : null,
          borderRadius: BorderRadius.circular(compact ? 14 : 16),
          border: Border.all(
            color: focused
                ? AppColors.cyan
                : hovered
                ? AppColors.cyan.withValues(alpha: 0.5)
                : AppColors.border,
            width: focused ? 1.6 : 1,
          ),
          boxShadow: focused
              ? [
                  BoxShadow(
                    color: AppColors.cyan.withValues(alpha: 0.28),
                    blurRadius: 26,
                    spreadRadius: 1,
                  ),
                ]
              : hovered
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        );

        return AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          clipBehavior: Clip.antiAlias,
          decoration: decoration,
          child: compact
              ? _CompactContent(
                  channel: channel,
                  isFavorite: isFavorite,
                  active: active,
                  onToggleFavorite: onToggleFavorite,
                )
              : _GridContent(
                  channel: channel,
                  isFavorite: isFavorite,
                  focused: focused,
                  onToggleFavorite: onToggleFavorite,
                ),
        );
      },
    );
  }
}

class _GridContent extends StatelessWidget {
  const _GridContent({
    required this.channel,
    required this.isFavorite,
    required this.focused,
    required this.onToggleFavorite,
  });

  final Channel channel;
  final bool isFavorite;
  final bool focused;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.6, -0.7),
                    radius: 1.1,
                    colors: [
                      AppColors.cyan.withValues(alpha: focused ? 0.14 : 0.06),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 10),
                child: ChannelLogo(channel: channel, radius: 14),
              ),
              Positioned(
                top: 10,
                left: 10,
                child: _LiveTag(highlighted: focused),
              ),
              Positioned(
                top: 7,
                right: 7,
                child: _FavoriteButton(
                  isFavorite: isFavorite,
                  onPressed: onToggleFavorite,
                  dense: true,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
          decoration: const BoxDecoration(
            color: Color(0x33000000),
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                channel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                channel.group,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompactContent extends StatelessWidget {
  const _CompactContent({
    required this.channel,
    required this.isFavorite,
    required this.active,
    required this.onToggleFavorite,
  });

  final Channel channel;
  final bool isFavorite;
  final bool active;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          ChannelLogo(channel: channel, width: 58, height: 56, radius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channel.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  channel.group,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _FavoriteButton(
            isFavorite: isFavorite,
            onPressed: onToggleFavorite,
            dense: false,
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.play_circle_fill_rounded,
            size: 27,
            color: active ? AppColors.cyan : AppColors.textFaint,
          ),
          const SizedBox(width: 2),
        ],
      ),
    );
  }
}

class _LiveTag extends StatelessWidget {
  const _LiveTag({required this.highlighted});

  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: highlighted ? AppColors.cyan : AppColors.success,
              boxShadow: highlighted
                  ? [
                      BoxShadow(
                        color: AppColors.cyan.withValues(alpha: 0.7),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'LIVE',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({
    required this.isFavorite,
    required this.onPressed,
    required this.dense,
  });

  final bool isFavorite;
  final VoidCallback onPressed;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Semantics(
          button: true,
          label: isFavorite ? 'Quitar de favoritos' : 'Añadir a favoritos',
          child: Container(
            padding: EdgeInsets.all(dense ? 6 : 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Icon(
              isFavorite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              size: dense ? 15 : 18,
              color: isFavorite ? const Color(0xFFFB7185) : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}
