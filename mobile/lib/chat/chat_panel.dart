import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../theme/theme.dart';
import 'chat_controller.dart';
import 'diff.dart';

const _toolLabels = <String, String>{
  'update_entity': 'Edit',
  'create_entity': 'New entity',
  'add_relationship': 'Add relationship',
  'remove_relationship': 'Remove relationship',
};

/// The non-modal, resizable floating panel (DESIGN.md decision 34). No scrim —
/// the content behind stays scrollable. Mounted by ChatHost above every route.
class ChatPanel extends StatefulWidget {
  final ChatController controller;
  const ChatPanel({super.key, required this.controller});

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  ChatController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_pinToBottom);
  }

  @override
  void dispose() {
    c.removeListener(_pinToBottom);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _pinToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _send() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    c.send(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = KronicleColors.of(context);
    final screenH = MediaQuery.of(context).size.height;

    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final height = (screenH * c.panelHeightFraction)
            .clamp(220.0, screenH * 0.9);
        return Material(
          color: theme.colorScheme.surface,
          elevation: 12, // a genuinely floating overlay keeps its shadow
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          child: SizedBox(
            height: height,
            child: Column(
              children: [
                _grip(colors),
                _header(context, colors),
                Divider(height: 1, color: colors.line),
                Expanded(child: _transcript(context, colors)),
                _composer(context, colors),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Drag handle that resizes the panel (dragging up grows it).
  Widget _grip(KronicleColors colors) {
    final screenH = MediaQuery.of(context).size.height;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (d) {
        c.panelHeightFraction =
            (c.panelHeightFraction - d.delta.dy / screenH).clamp(0.3, 0.9);
        setState(() {});
      },
      child: Container(
        height: 22,
        alignment: Alignment.center,
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: colors.line,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, KronicleColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 8, 8),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 16, color: colors.accentInk),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Chat',
                    style: TextStyle(
                      fontFamily: KronicleTheme.ui,
                      fontWeight: FontWeight.w600,
                      color: theme(context).colorScheme.onSurface,
                    )),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(
                          color: theme(context).colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: colors.line),
                        ),
                        child: Text(
                          c.contextLabel,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: KronicleTheme.ui,
                            fontSize: 11,
                            color: colors.inkMuted,
                          ),
                        ),
                      ),
                    ),
                    if (c.hasEntityFocus)
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: const Size(0, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: colors.accentInk,
                        ),
                        onPressed: () => c.setDetached(!c.detached),
                        child: Text(
                          c.detached ? 'focus page' : 'whole vault',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (c.turns.isNotEmpty)
            IconButton(
              tooltip: 'Clear chat',
              icon: const Icon(Icons.delete_sweep_outlined, size: 20),
              onPressed: c.busy ? null : c.clear,
            ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close, size: 20),
            onPressed: c.close,
          ),
        ],
      ),
    );
  }

  ThemeData theme(BuildContext context) => Theme.of(context);

  Widget _transcript(BuildContext context, KronicleColors colors) {
    if (c.turns.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            'Chatting about ${c.contextLabel}. Ask for a rewrite and you\'ll get '
            'a diff to apply or discard — clear it any time to start over.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: KronicleTheme.ui,
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: colors.inkFaint,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      itemCount: c.turns.length + (c.busy ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= c.turns.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                const SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Text('thinking…',
                    style: TextStyle(
                        fontFamily: KronicleTheme.ui,
                        fontSize: 12,
                        color: colors.inkFaint)),
              ],
            ),
          );
        }
        final t = c.turns[i];
        return t.role == 'user'
            ? _userTurn(context, colors, t)
            : _assistantTurn(context, colors, t);
      },
    );
  }

  Widget _userTurn(BuildContext context, KronicleColors colors, Turn t) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, left: 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.accentSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          t.text,
          style: TextStyle(
            fontFamily: KronicleTheme.ui,
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _assistantTurn(BuildContext context, KronicleColors colors, Turn t) {
    final body = visibleChatText(t.text);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final note in t.reading)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.search, size: 13, color: colors.inkFaint),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(note,
                        style: TextStyle(
                            fontFamily: KronicleTheme.ui,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: colors.inkFaint)),
                  ),
                ],
              ),
            ),
          if (body.isNotEmpty)
            MarkdownBody(
              data: body,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                p: TextStyle(
                  fontFamily: KronicleTheme.ui,
                  fontSize: 14,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          for (final p in t.proposals) _proposalCard(context, colors, p),
        ],
      ),
    );
  }

  Widget _proposalCard(BuildContext context, KronicleColors colors, Proposal p) {
    final discarded = p.status == ProposalStatus.discarded;
    final actionable = p.status == ProposalStatus.pending ||
        p.status == ProposalStatus.failed ||
        p.status == ProposalStatus.applying;
    final content = p.args['content'];

    return Opacity(
      opacity: discarded ? 0.5 : 1,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.accentSoft,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: colors.accentInk.withValues(alpha: 0.4)),
                  ),
                  child: Text(_toolLabels[p.tool] ?? p.tool,
                      style: TextStyle(
                          fontFamily: KronicleTheme.ui,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.accentInk)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(p.summary,
                      style: TextStyle(
                          fontFamily: KronicleTheme.ui,
                          fontSize: 12.5,
                          height: 1.4,
                          color: Theme.of(context).colorScheme.onSurface)),
                ),
                _statusBadge(colors, p.status),
              ],
            ),
            if (actionable) ...[
              if (p.tool == 'update_entity' && content is String)
                _diffView(context, colors, p.args['id'] as String? ?? '', content),
              ..._argRows(context, colors, p),
              if (p.tool == 'create_entity' && content is String && content.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: KronicleTheme.prose,
                          fontSize: 12.5,
                          fontStyle: FontStyle.italic,
                          color: colors.inkMuted)),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: p.status == ProposalStatus.applying
                        ? null
                        : () => c.discard(p),
                    style: TextButton.styleFrom(foregroundColor: colors.inkMuted),
                    child: const Text('Discard'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed:
                        p.status == ProposalStatus.applying ? null : () => c.apply(p),
                    child: p.status == ProposalStatus.applying
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Apply'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(KronicleColors colors, ProposalStatus status) {
    switch (status) {
      case ProposalStatus.applied:
        return _badge('Applied', colors.canon, Icons.check);
      case ProposalStatus.discarded:
        return Text('Discarded',
            style: TextStyle(
                fontFamily: KronicleTheme.ui, fontSize: 11, color: colors.inkFaint));
      case ProposalStatus.failed:
        return _badge('Failed', colors.rejected, Icons.error_outline);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _badge(String text, Color color, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(text,
              style: TextStyle(
                  fontFamily: KronicleTheme.ui,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ]),
      );

  List<Widget> _argRows(BuildContext context, KronicleColors colors, Proposal p) {
    final rows = <Widget>[];
    p.args.forEach((k, v) {
      if (k == 'id' || k == 'content') return;
      final value = v == null ? '—' : (v is String ? v : v.toString());
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$k  ',
                style: TextStyle(
                    fontFamily: KronicleTheme.editor,
                    fontSize: 11.5,
                    color: colors.inkFaint)),
            Expanded(
              child: Text(value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: KronicleTheme.ui,
                      fontSize: 11.5,
                      color: colors.inkMuted)),
            ),
          ],
        ),
      ));
    });
    return rows;
  }

  Widget _diffView(
      BuildContext context, KronicleColors colors, String id, String after) {
    final rows = unifiedDiff(c.diffBase(id), after);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.line),
      ),
      child: Scrollbar(
        child: ListView.builder(
          padding: const EdgeInsets.all(8),
          shrinkWrap: true,
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final r = rows[i];
            if (r.kind == DiffKind.skip) {
              return Text('⋯ ${r.count} unchanged lines',
                  style: TextStyle(
                      fontFamily: KronicleTheme.editor,
                      fontSize: 11,
                      color: colors.inkFaint));
            }
            final (color, prefix, bg, strike) = switch (r.kind) {
              DiffKind.add => (colors.canon, '+', colors.canon.withValues(alpha: 0.1), false),
              DiffKind.del => (colors.rejected, '−', colors.rejected.withValues(alpha: 0.1), true),
              _ => (colors.inkMuted, ' ', Colors.transparent, false),
            };
            return Container(
              color: bg,
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              child: Text(
                '$prefix ${r.text}',
                style: TextStyle(
                  fontFamily: KronicleTheme.editor,
                  fontSize: 11,
                  height: 1.4,
                  color: color,
                  decoration: strike ? TextDecoration.lineThrough : null,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _composer(BuildContext context, KronicleColors colors) {
    return Container(
      // The host lifts the whole panel above the keyboard, so the composer no
      // longer pads for it itself.
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              // Android keyboards (Gboard) keep a "composing region" underline
              // over the word in progress. Deleting inside that region then
              // typing makes the IME re-commit its own stale copy of the word,
              // so already-deleted text reappears (type 'abcde', delete 'cde',
              // type 'xyz' → 'abcdexyz'). Disabling autocorrect/suggestions
              // alone didn't stop it — the region persists regardless. The fix
              // is to collapse composing to empty after every edit, forcing the
              // IME to start each keystroke from the field's real text so
              // deletes always stick. (Trade-off: no on-the-fly composition for
              // CJK/IME-heavy scripts — fine for this English-only tool.)
              inputFormatters: [
                TextInputFormatter.withFunction(
                  (_, newValue) =>
                      newValue.copyWith(composing: TextRange.empty),
                ),
              ],
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'Ask about ${c.contextLabel}…',
                isDense: true,
              ),
              style: const TextStyle(fontFamily: KronicleTheme.ui, fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: c.busy ? null : _send,
            icon: const Icon(Icons.arrow_upward, size: 20),
          ),
        ],
      ),
    );
  }
}
