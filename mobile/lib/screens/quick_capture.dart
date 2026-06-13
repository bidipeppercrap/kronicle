import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme/theme.dart';

/// The core loop of an ideas vault: getting an idea in must be ONE step, not a
/// form with a type picker (DESIGN.md). Name + optional note → a `stub` of type
/// `lore` (the server defaults), corrected later at triage. Returns true if
/// something was captured, so the caller can refresh.
Future<bool> showQuickCapture(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => const _QuickCaptureSheet(),
  );
  return result ?? false;
}

class _QuickCaptureSheet extends StatefulWidget {
  const _QuickCaptureSheet();

  @override
  State<_QuickCaptureSheet> createState() => _QuickCaptureSheetState();
}

class _QuickCaptureSheetState extends State<_QuickCaptureSheet> {
  final _name = TextEditingController();
  final _note = TextEditingController();
  bool _noteOpen = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final note = _note.text.trim();
      await ApiClient.instance.createEntity({
        'name': name,
        if (note.isNotEmpty) 'summary': note,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = KronicleColors.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Capture an idea',
            style: TextStyle(
              fontFamily: KronicleTheme.ui,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _capture(),
            decoration: const InputDecoration(hintText: 'Name'),
            style: const TextStyle(fontFamily: KronicleTheme.ui),
          ),
          if (_noteOpen) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'A note (optional)'),
              style: const TextStyle(fontFamily: KronicleTheme.ui),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (!_noteOpen)
                TextButton.icon(
                  onPressed: () => setState(() => _noteOpen = true),
                  icon: const Icon(Icons.notes, size: 16),
                  label: const Text('Add a note'),
                  style: TextButton.styleFrom(foregroundColor: colors.inkMuted),
                ),
              const Spacer(),
              FilledButton(
                onPressed: _saving ? null : _capture,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Capture'),
              ),
            ],
          ),
          Text(
            'Saved as a stub — triage it to a type and status later.',
            style: TextStyle(
              fontFamily: KronicleTheme.ui,
              fontSize: 11.5,
              color: colors.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}
