import 'package:flutter/material.dart';

import '../core/app_layout.dart';
import '../models/channel.dart';
import 'channel_card.dart';

/// Lista o cuadrícula de canales adaptada al dispositivo.
class ChannelCollection extends StatelessWidget {
  const ChannelCollection({
    super.key,
    required this.channels,
    required this.layout,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.isFavorite,
    this.padding = EdgeInsets.zero,
    this.shrinkWrap = false,
    this.physics,
    this.controller,
    this.emptyState,
  });

  final List<Channel> channels;
  final AppLayout layout;
  final ValueChanged<Channel> onOpen;
  final ValueChanged<Channel> onToggleFavorite;
  final bool Function(Channel channel) isFavorite;
  final EdgeInsets padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final ScrollController? controller;
  final Widget? emptyState;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return emptyState ?? const SizedBox.shrink();
    }

    if (layout.isPhone) {
      return ListView.separated(
        controller: controller,
        shrinkWrap: shrinkWrap,
        physics: physics,
        padding: padding,
        itemCount: channels.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final channel = channels[index];
          return ChannelCard(
            key: ValueKey('compact-${channel.url}-$index'),
            channel: channel,
            isFavorite: isFavorite(channel),
            compact: true,
            layout: layout,
            onTap: () => onOpen(channel),
            onToggleFavorite: () => onToggleFavorite(channel),
          );
        },
      );
    }

    return GridView.builder(
      controller: controller,
      shrinkWrap: shrinkWrap,
      physics: physics,
      padding: padding,
      clipBehavior: Clip.none,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: layout.gridMaxExtent,
        childAspectRatio: layout.gridAspectRatio,
        mainAxisSpacing: layout.gridSpacing,
        crossAxisSpacing: layout.gridSpacing,
      ),
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channel = channels[index];
        return ChannelCard(
          key: ValueKey('grid-${channel.url}-$index'),
          channel: channel,
          isFavorite: isFavorite(channel),
          layout: layout,
          onTap: () => onOpen(channel),
          onToggleFavorite: () => onToggleFavorite(channel),
        );
      },
    );
  }
}
