import 'package:flutter/material.dart';

import '../nav.dart';
import 'chat_controller.dart';
import 'chat_panel.dart';

/// Mounts the route-aware AI chat above every route (DESIGN.md decision 34):
/// an app-wide draggable bubble that opens a non-modal, resizable floating
/// panel with no scrim, so the screen behind stays scrollable while chatting.
class ChatHost extends StatefulWidget {
  final Widget child;
  const ChatHost({super.key, required this.child});

  @override
  State<ChatHost> createState() => _ChatHostState();
}

class _ChatHostState extends State<ChatHost> {
  final _c = ChatController.instance;
  static const _bubbleSize = 56.0;

  @override
  void initState() {
    super.initState();
    _c.toast = _showToast;
  }

  void _showToast(String message, {bool error = false}) {
    final messenger = scaffoldMessengerKey.currentState;
    if (messenger == null) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final pad = MediaQuery.of(context).padding;

    // Default the bubble to the bottom-right, clear of the nav bar.
    _c.bubbleOffset ??= Offset(
      size.width - _bubbleSize - 16,
      size.height - _bubbleSize - pad.bottom - 96,
    );

    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        return Stack(
          children: [
            Positioned.fill(child: widget.child),
            if (_c.open)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ChatPanel(controller: _c),
              ),
            if (!_c.open) _bubble(size, pad),
          ],
        );
      },
    );
  }

  Widget _bubble(Size size, EdgeInsets pad) {
    final scheme = Theme.of(context).colorScheme;
    final offset = _c.bubbleOffset!;
    return Positioned(
      left: offset.dx,
      top: offset.dy,
      child: GestureDetector(
        onTap: _c.toggle,
        onPanUpdate: (d) {
          final next = offset + d.delta;
          _c.bubbleOffset = Offset(
            next.dx.clamp(8.0, size.width - _bubbleSize - 8),
            next.dy.clamp(pad.top + 8, size.height - _bubbleSize - 8),
          );
          setState(() {});
        },
        child: Container(
          width: _bubbleSize,
          height: _bubbleSize,
          decoration: BoxDecoration(
            color: scheme.primary,
            shape: BoxShape.circle,
            // A subtle shadow — this is the one floating affordance that keeps
            // "mostly flat" honest (DESIGN.md decision 35).
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(Icons.auto_awesome, color: scheme.onPrimary, size: 24),
        ),
      ),
    );
  }
}
