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
  static const _margin = 16.0;

  // True while a drag is in flight — disables the snap animation so the bubble
  // tracks the finger, then re-enables it for the fly-to-edge release.
  bool _dragging = false;

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

    // Default the bubble to the bottom-right, lifted clear of the Capture FAB
    // (which also lives bottom-right above the nav bar) so the two never
    // overlap on first run — the writer can still drag it anywhere after.
    _c.bubbleOffset ??= Offset(
      size.width - _bubbleSize - _margin,
      size.height - _bubbleSize - pad.bottom - 168,
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
                // Ride above the soft keyboard so the composer and transcript
                // stay visible while typing, instead of being covered by it.
                bottom: MediaQuery.of(context).viewInsets.bottom,
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
    final minY = pad.top + 8;
    final maxY = size.height - _bubbleSize - 8;
    return AnimatedPositioned(
      // No animation while dragging (the finger drives it); a quick eased glide
      // for the fly-to-edge snap on release, like the Messenger bubble.
      duration: _dragging ? Duration.zero : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      left: offset.dx,
      top: offset.dy,
      child: GestureDetector(
        onTap: _c.toggle,
        onPanStart: (_) => setState(() => _dragging = true),
        onPanUpdate: (d) {
          // Accumulate from the *live* offset, not the build-time capture, so a
          // fast flick tracks the finger 1:1 instead of dropping deltas (and
          // appearing to lag) when several move events land in one frame.
          final next = _c.bubbleOffset! + d.delta;
          _c.bubbleOffset = Offset(
            next.dx.clamp(8.0, size.width - _bubbleSize - 8),
            next.dy.clamp(minY, maxY),
          );
          setState(() {});
        },
        onPanEnd: (_) {
          // Anchor to whichever side edge the bubble's centre is nearer.
          final center = _c.bubbleOffset!.dx + _bubbleSize / 2;
          final toRight = center >= size.width / 2;
          _c.bubbleOffset = Offset(
            toRight ? size.width - _bubbleSize - _margin : _margin,
            _c.bubbleOffset!.dy.clamp(minY, maxY),
          );
          setState(() => _dragging = false);
        },
        child: Container(
          width: _bubbleSize,
          height: _bubbleSize,
          decoration: BoxDecoration(
            color: scheme.primary,
            shape: BoxShape.circle,
            // A soft shadow — this is the one floating affordance that keeps
            // "mostly flat" honest (DESIGN.md decision 35).
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(Icons.auto_awesome, color: scheme.onPrimary, size: 24),
        ),
      ),
    );
  }
}
