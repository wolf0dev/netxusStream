import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Envoltorio interactivo con enfoque de TV, hover de ratón y activación por
/// teclado/control remoto. Centraliza el efecto de brillo de la app.
class NexusFocusable extends StatefulWidget {
  const NexusFocusable({
    super.key,
    required this.builder,
    required this.onTap,
    this.onLongPress,
    this.autofocus = false,
    this.focusNode,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.focusedScale = 1.03,
    this.pressedScale = 0.985,
    this.enabled = true,
    this.semanticLabel,
    this.onFocusChange,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget Function(BuildContext context, bool focused, bool hovered)
  builder;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool autofocus;
  final FocusNode? focusNode;
  final BorderRadius borderRadius;
  final double focusedScale;
  final double pressedScale;
  final bool enabled;
  final String? semanticLabel;
  final ValueChanged<bool>? onFocusChange;
  final MouseCursor cursor;

  @override
  State<NexusFocusable> createState() => _NexusFocusableState();
}

class _NexusFocusableState extends State<NexusFocusable> {
  FocusNode? _internalNode;
  bool _focused = false;
  bool _hovered = false;
  bool _pressed = false;

  FocusNode get _node => widget.focusNode ?? _internalNode!;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _internalNode = FocusNode(debugLabel: 'NexusFocusable');
    }
    _node.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant NexusFocusable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChange);
      _internalNode?.removeListener(_handleFocusChange);
      if (widget.focusNode == null) {
        _internalNode = FocusNode(debugLabel: 'NexusFocusable');
      }
      _node.addListener(_handleFocusChange);
    }
  }

  void _handleFocusChange() {
    final focused = _node.hasFocus;
    if (focused != _focused) {
      setState(() => _focused = focused);
      widget.onFocusChange?.call(focused);
    }
  }

  @override
  void dispose() {
    _node.removeListener(_handleFocusChange);
    _internalNode?.dispose();
    super.dispose();
  }

  void _activate() {
    if (!widget.enabled) return;
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: _node,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      mouseCursor: widget.enabled ? widget.cursor : SystemMouseCursors.basic,
      onShowHoverHighlight: (value) {
        if (value != _hovered) setState(() => _hovered = value);
      },
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        enabled: widget.enabled,
        label: widget.semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _activate,
          onLongPress: widget.onLongPress,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: AnimatedScale(
            scale: _pressed
                ? widget.pressedScale
                : (_focused ? widget.focusedScale : 1.0),
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            child: widget.builder(context, _focused, _hovered),
          ),
        ),
      ),
    );
  }
}
