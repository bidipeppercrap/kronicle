import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../theme/theme.dart';
import '../widgets/status_chip.dart';

/// A server-driven entity search picker — used for relationship targets and
/// the parent selector. Returns the chosen entity, or null if dismissed.
Future<Entity?> showEntityPicker(BuildContext context, {String? title}) {
  return showModalBottomSheet<Entity>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => _EntityPickerSheet(title: title ?? 'Find an entity'),
  );
}

class _EntityPickerSheet extends StatefulWidget {
  final String title;
  const _EntityPickerSheet({required this.title});

  @override
  State<_EntityPickerSheet> createState() => _EntityPickerSheetState();
}

class _EntityPickerSheetState extends State<_EntityPickerSheet> {
  Timer? _debounce;
  Future<List<Entity>>? _future;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    if (q.isEmpty) {
      setState(() => _future = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() => _future = ApiClient.instance.search(q).then((p) => p.items));
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = KronicleColors.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: widget.title,
                prefixIcon: const Icon(Icons.search, size: 20),
              ),
              style: const TextStyle(fontFamily: KronicleTheme.ui),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _future == null
                  ? Center(
                      child: Text(
                        'Type to search the vault.',
                        style: TextStyle(
                          fontFamily: KronicleTheme.ui,
                          color: colors.inkFaint,
                        ),
                      ),
                    )
                  : FutureBuilder<List<Entity>>(
                      future: _future,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final items = snap.data ?? [];
                        if (items.isEmpty) {
                          return Center(
                            child: Text(
                              'No matches.',
                              style: TextStyle(
                                fontFamily: KronicleTheme.ui,
                                color: colors.inkFaint,
                              ),
                            ),
                          );
                        }
                        return ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, _) =>
                              Divider(height: 1, color: colors.line),
                          itemBuilder: (_, i) {
                            final e = items[i];
                            return ListTile(
                              title: Text(
                                e.name,
                                style: const TextStyle(
                                  fontFamily: KronicleTheme.ui,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                e.typeLabel,
                                style: TextStyle(
                                  fontFamily: KronicleTheme.ui,
                                  color: colors.inkMuted,
                                ),
                              ),
                              trailing: StatusChip(e.status, dense: true),
                              onTap: () => Navigator.pop(context, e),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
