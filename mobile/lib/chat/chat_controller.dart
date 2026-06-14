import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../api/api_client.dart';
import '../state/chat_context.dart';

final _chatMarker = RegExp(r'\[(?:Proposed|Context)\b[^\]]*\]');
// A marker still mid-stream (closing bracket not in yet) — its dangling tail.
final _chatMarkerTail = RegExp(r'\[(?:Proposed|Context)\b[^\]]*$');

/// Strip the app-record markers ([Proposed …], [Context: …]) from assistant
/// text. The client injects these into wire history as bookkeeping; the model is
/// told never to type them, but sometimes it parrots a "[Proposed … — applied]"
/// line as prose instead of calling a write tool — faking a proposal with no
/// Apply button (and a "change" that never happened). Scrubbing them from both
/// the rendered bubble and the history sent back keeps the fake off screen and
/// stops it reinforcing itself next turn. Real proposals arrive as cards, so
/// nothing real is lost. Only ever applied to assistant text — the [Context: …]
/// prefix on user turns is a deliberate, separate marker.
String visibleChatText(String raw) => raw
    .replaceAll(_chatMarker, '')
    .replaceAll(_chatMarkerTail, '')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

enum ProposalStatus { pending, applying, applied, discarded, failed }

class Proposal {
  final String id;
  final String tool;
  final String summary;
  final Map<String, dynamic> args;
  ProposalStatus status;
  Proposal({
    required this.id,
    required this.tool,
    required this.summary,
    required this.args,
    this.status = ProposalStatus.pending,
  });
}

class Turn {
  final String role; // 'user' | 'assistant'
  String text;

  /// The [Context: …] marker emitted with this user turn — wire-only, hidden.
  String? context;
  final List<Proposal> proposals = [];
  final List<String> reading = [];
  Turn(this.role, {this.text = '', this.context});
}

class _Effective {
  final String? entityId;
  final String label;
  final String marker;
  const _Effective(this.entityId, this.label, this.marker);
}

const _vaultMarker = 'now browsing the whole vault';

/// The route-aware chat: conversation state + overlay state for the single
/// shell-mounted panel (DESIGN.md decision 33/34). Stateless on the server —
/// this holds the whole conversation and sends it every turn; closing ends it.
class ChatController extends ChangeNotifier {
  ChatController._() {
    // Navigating to a new focus re-attaches the chat there (clears a manual
    // "talk to the whole vault" detach), mirroring the web reset-on-navigation.
    ChatContextModel.instance.addListener(_onFocusChanged);
  }
  static final ChatController instance = ChatController._();

  // ——— Overlay state ———
  bool open = false;
  Offset? bubbleOffset; // null until the host positions it
  double panelHeightFraction = 0.5;

  // ——— Conversation state ———
  final List<Turn> turns = [];
  bool busy = false;
  String? _lastSentMarker;
  bool detached = false;
  final Map<String, String> baselines = {};

  /// Host-supplied toast sink (the controller is not a widget).
  void Function(String message, {bool error})? toast;

  @override
  void dispose() {
    ChatContextModel.instance.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    detached = false;
    notifyListeners();
  }

  void toggle() {
    open = !open;
    notifyListeners();
  }

  void close() {
    open = false;
    notifyListeners();
  }

  void setDetached(bool v) {
    detached = v;
    notifyListeners();
  }

  /// Wipe the conversation back to a blank slate. The controller is a singleton,
  /// so the conversation survives closing the panel — this is the one-tap way to
  /// start over: transcript, the context markers, fetched baselines, and any
  /// manual whole-vault detach all reset. Nothing is ever written server-side.
  void clear() {
    turns.clear();
    baselines.clear();
    _lastSentMarker = null;
    detached = false;
    notifyListeners();
  }

  bool get hasEntityFocus => ChatContextModel.instance.current != null;

  _Effective get _effective {
    if (detached) return const _Effective(null, 'whole vault', _vaultMarker);
    final f = ChatContextModel.instance.current;
    if (f != null) return _Effective(f.entityId, f.name, f.marker);
    return const _Effective(null, 'whole vault', _vaultMarker);
  }

  String get contextLabel => _effective.label;

  /// Best-known baseline to diff an update_entity proposal against.
  String diffBase(String id) {
    final bridge = EditorBridge.instance;
    if (bridge.entityId == id && bridge.currentContent != null) {
      return bridge.currentContent!();
    }
    final f = ChatContextModel.instance.current;
    if (f?.entityId == id) return f!.content;
    return baselines[id] ?? '';
  }

  Future<void> _ensureBaseline(String id) async {
    if (EditorBridge.instance.entityId == id) return;
    if (ChatContextModel.instance.current?.entityId == id) return;
    if (baselines.containsKey(id)) return;
    baselines[id] = '';
    try {
      final e = await ApiClient.instance.getEntity(id);
      baselines[id] = e.content;
      notifyListeners();
    } catch (_) {
      // Leave the empty baseline — the diff renders as all-new.
    }
  }

  /// Wire-format history: plain {role, content}. Proposals + their outcomes and
  /// the [Context: …] markers are flattened into the turns, so the model knows
  /// next turn what landed and where focus is — the server remembers nothing.
  List<Map<String, String>> _wireHistory() {
    final msgs = <Map<String, String>>[];
    for (final t in turns) {
      if (t.role == 'user') {
        final content =
            t.context != null ? '[Context: ${t.context}]\n\n${t.text}' : t.text;
        msgs.add({'role': 'user', 'content': content});
        continue;
      }
      var content = visibleChatText(t.text);
      for (final p in t.proposals) {
        final outcome = p.status == ProposalStatus.applied
            ? 'applied'
            : p.status == ProposalStatus.discarded
                ? 'discarded'
                : 'pending';
        content += '\n\n[Proposed ${p.id}: ${p.summary} — $outcome]';
      }
      if (content.trim().isNotEmpty) {
        msgs.add({'role': 'assistant', 'content': content.trim()});
      }
    }
    return msgs;
  }

  Future<void> send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || busy) return;

    // Tag the turn with a context marker whenever focus differs from the last
    // one sent (including the first message), so the transcript stays
    // self-describing as the writer navigates. Wire-only — never shown.
    final eff = _effective;
    final context = eff.marker != _lastSentMarker ? eff.marker : null;
    _lastSentMarker = eff.marker;
    final entityId = eff.entityId;

    turns.add(Turn('user', text: text, context: context));
    final history = _wireHistory();
    final turn = Turn('assistant');
    turns.add(turn);
    busy = true;
    notifyListeners();

    try {
      final res = await ApiClient.instance.chatStream({
        'entity_id': entityId,
        'messages': history,
      });
      if (res.statusCode != 200) {
        final body = await res.stream.bytesToString();
        String msg = 'Chat failed (${res.statusCode})';
        try {
          final j = jsonDecode(body);
          if (j is Map && j['error'] is String) msg = j['error'] as String;
        } catch (_) {}
        throw Exception(msg);
      }

      var buf = '';
      await for (final chunk in res.stream.transform(utf8.decoder)) {
        buf += chunk;
        var i = buf.indexOf('\n\n');
        while (i >= 0) {
          final block = buf.substring(0, i);
          buf = buf.substring(i + 2);
          var event = 'message';
          var data = '';
          for (final line in block.split('\n')) {
            if (line.startsWith('event:')) {
              event = line.substring(6).trim();
            } else if (line.startsWith('data:')) {
              data += line.substring(5).trim();
            }
          }
          if (data.isNotEmpty) {
            _handleEvent(turn, event, jsonDecode(data) as Map<String, dynamic>);
          }
          i = buf.indexOf('\n\n');
        }
      }
    } catch (e) {
      toast?.call('$e'.replaceFirst('Exception: ', ''), error: true);
      if (turn.text.isEmpty && turn.proposals.isEmpty) turns.remove(turn);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _handleEvent(Turn turn, String event, Map<String, dynamic> data) {
    switch (event) {
      case 'text':
        turn.text += (data['delta'] ?? '').toString();
        notifyListeners();
      case 'reading':
        final detail = (data['detail'] ?? '').toString();
        final tool = (data['tool'] ?? 'the vault').toString();
        turn.reading.add('checking ${detail.isNotEmpty ? detail : tool}…');
        notifyListeners();
      case 'proposal':
        if (data['tool'] == 'apply_proposal') {
          // Consent came from the writer's own message — apply the referenced
          // pending proposal right away. Only proposals from *earlier* turns
          // qualify; one born this turn was never seen (DESIGN.md).
          final refId = (data['args'] as Map?)?['id'];
          Proposal? ref;
          for (final t in turns) {
            if (identical(t, turn)) continue;
            for (final p in t.proposals) {
              if (p.id == refId &&
                  (p.status == ProposalStatus.pending ||
                      p.status == ProposalStatus.failed)) {
                ref = p;
              }
            }
          }
          if (ref != null) {
            apply(ref);
          } else if (turn.proposals.any((p) => p.id == refId)) {
            toast?.call(
                'The AI tried to apply its own new proposal — review it below',
                error: true);
          } else {
            toast?.call('No pending proposal ${refId ?? ''} to apply',
                error: true);
          }
        } else {
          final p = Proposal(
            id: data['id'] as String,
            tool: data['tool'] as String,
            summary: (data['summary'] ?? '').toString(),
            args: (data['args'] as Map?)?.cast<String, dynamic>() ?? {},
          );
          turn.proposals.add(p);
          if (p.tool == 'update_entity' && p.args['id'] is String) {
            _ensureBaseline(p.args['id'] as String);
          }
          notifyListeners();
        }
      case 'error':
        toast?.call((data['message'] ?? 'AI chat failed').toString(),
            error: true);
    }
  }

  /// Apply = dumb dispatch through the normal REST save path, then refresh
  /// (DESIGN.md). The exception: an update to the entity open in the editor
  /// merges into its live buffer instead, so a PUT can't clobber unsaved prose.
  Future<void> apply(Proposal p) async {
    if (p.status == ProposalStatus.applying ||
        p.status == ProposalStatus.applied) {
      return;
    }
    p.status = ProposalStatus.applying;
    notifyListeners();
    final api = ApiClient.instance;
    try {
      switch (p.tool) {
        case 'update_entity':
          final id = p.args['id'] as String;
          final fields = Map<String, dynamic>.of(p.args)..remove('id');
          final bridge = EditorBridge.instance;
          if (bridge.entityId == id && bridge.applyUpdate != null) {
            bridge.applyUpdate!(fields);
          } else {
            await api.updateEntity(id, fields);
            RefreshBus.instance.bump();
          }
        case 'create_entity':
          await api.createEntity(p.args);
          RefreshBus.instance.bump();
        case 'add_relationship':
          await api.createRelationship(p.args);
          RefreshBus.instance.bump();
        case 'remove_relationship':
          await api.deleteRelationship(p.args['id'] as String);
          RefreshBus.instance.bump();
        default:
          throw Exception('Unknown proposal tool: ${p.tool}');
      }
      p.status = ProposalStatus.applied;
      toast?.call('Applied — ${p.summary}');
    } catch (e) {
      p.status = ProposalStatus.failed;
      toast?.call('$e'.replaceFirst('Exception: ', ''), error: true);
    }
    notifyListeners();
  }

  void discard(Proposal p) {
    p.status = ProposalStatus.discarded;
    notifyListeners();
  }
}
