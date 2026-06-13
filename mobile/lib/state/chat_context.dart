import 'package:flutter/foundation.dart';

import '../api/models.dart';

/// What the route-aware chat is currently focused on (DESIGN.md, route-aware
/// chat). Mirrors the entity the writer is viewing/editing; null means they're
/// browsing the vault (list, timeline, search, home).
class ChatFocus {
  final String entityId;
  final String name;
  final String type;
  final String status;
  final String content;
  final String summary;

  const ChatFocus({
    required this.entityId,
    required this.name,
    required this.type,
    required this.status,
    required this.content,
    required this.summary,
  });

  factory ChatFocus.fromEntity(Entity e) => ChatFocus(
        entityId: e.id,
        name: e.name,
        type: e.type,
        status: e.status,
        content: e.content,
        summary: e.summary,
      );

  /// The [Context: …] marker emitted when this becomes the live focus.
  String get marker => 'now viewing $name ($type, $status)';
}

class _Entry {
  final Object key;
  ChatFocus focus;
  _Entry(this.key, this.focus);
}

/// A stack of foci, one per live entity route. Detail/editor screens push their
/// entity on mount and remove it on dispose, so popping back to a list reveals
/// the previous focus (or none → the whole vault). This is how the single
/// shell-mounted chat "follows the route" without a router (DESIGN.md).
class ChatContextModel extends ChangeNotifier {
  ChatContextModel._();
  static final ChatContextModel instance = ChatContextModel._();

  final List<_Entry> _stack = [];

  ChatFocus? get current => _stack.isEmpty ? null : _stack.last.focus;

  Object push(ChatFocus focus) {
    final key = Object();
    _stack.add(_Entry(key, focus));
    notifyListeners();
    return key;
  }

  /// Refresh a focus already on the stack (e.g. content edited, status changed).
  void update(Object key, ChatFocus focus) {
    final wasTop = _stack.isNotEmpty && _stack.last.key == key;
    for (final e in _stack) {
      if (e.key == key) {
        e.focus = focus;
        if (wasTop) notifyListeners();
        return;
      }
    }
  }

  void remove(Object key) {
    final before = current;
    _stack.removeWhere((e) => e.key == key);
    if (!identical(before, current)) notifyListeners();
  }
}

/// Bumped after a chat proposal is applied through REST, so on-screen views
/// (detail, list, …) refetch — the mobile equivalent of the web's
/// `invalidateAll()` (DESIGN.md, "Apply"). Screens that show server data
/// listen and reload.
class RefreshBus extends ChangeNotifier {
  RefreshBus._();
  static final RefreshBus instance = RefreshBus._();
  void bump() => notifyListeners();
}

/// Lets an applied chat proposal merge into an open editor's live buffer
/// instead of PUTting around it — a global panel must not clobber unsaved
/// prose (DESIGN.md, "Apply"). The editor registers while mounted.
class EditorBridge extends ChangeNotifier {
  EditorBridge._();
  static final EditorBridge instance = EditorBridge._();

  String? entityId;
  void Function(Map<String, dynamic> fields)? applyUpdate;
  String Function()? currentContent;

  void register({
    required String entityId,
    required void Function(Map<String, dynamic>) applyUpdate,
    required String Function() currentContent,
  }) {
    this.entityId = entityId;
    this.applyUpdate = applyUpdate;
    this.currentContent = currentContent;
  }

  void unregister(String entityId) {
    if (this.entityId == entityId) {
      this.entityId = null;
      applyUpdate = null;
      currentContent = null;
    }
  }
}
