import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../state/chat_context.dart';
import '../theme/theme.dart';
import '../widgets/async_view.dart';
import 'entity_picker.dart';

/// Basic editing (Phase 2): name, type, status, summary, the Markdown prose
/// field, tags, and a relationship picker. Registers with the EditorBridge so
/// an applied chat edit (Phase 4) merges into this live buffer instead of
/// PUTting around unsaved prose (DESIGN.md, "Apply").
class EditorScreen extends StatefulWidget {
  /// Edit an existing entity, or…
  final Entity? entity;

  /// …create a new one of this type (defaults to character).
  final String? createType;

  const EditorScreen({super.key, this.entity, this.createType});

  bool get isCreate => entity == null;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final _name = TextEditingController();
  final _summary = TextEditingController();
  final _content = TextEditingController();

  late String _type;
  late String _status;
  String? _parentId;
  String? _parentName;
  List<String> _tags = [];
  Map<String, dynamic> _metadata = {};

  bool _saving = false;

  // Edit-mode relationships.
  List<Relationship> _relationships = [];
  final Map<String, EntityRef> _refs = {};
  bool _relLoading = false;

  @override
  void initState() {
    super.initState();
    final e = widget.entity;
    if (e != null) {
      _name.text = e.name;
      _summary.text = e.summary;
      _content.text = e.content;
      _type = e.type;
      _status = e.status;
      _parentId = e.parentId;
      _tags = List.of(e.tags);
      _metadata = Map.of(e.metadata)..remove('tags');
      _loadRelationships(e);
      EditorBridge.instance.register(
        entityId: e.id,
        applyUpdate: _applyChatUpdate,
        currentContent: () => _content.text,
      );
    } else {
      _type = widget.createType ?? 'character';
      _status = 'draft';
    }
  }

  @override
  void dispose() {
    if (widget.entity != null) EditorBridge.instance.unregister(widget.entity!.id);
    _name.dispose();
    _summary.dispose();
    _content.dispose();
    super.dispose();
  }

  /// Merge an applied chat proposal into the open buffer (DESIGN.md).
  void _applyChatUpdate(Map<String, dynamic> fields) {
    setState(() {
      if (fields['name'] is String) _name.text = fields['name'] as String;
      if (fields['summary'] is String) _summary.text = fields['summary'] as String;
      if (fields['content'] is String) _content.text = fields['content'] as String;
      if (fields['metadata'] is Map) {
        final m = (fields['metadata'] as Map).cast<String, dynamic>();
        final t = m['tags'];
        if (t is List) _tags = t.map((e) => e.toString()).toList();
        _metadata = Map.of(m)..remove('tags');
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Applied into the editor — save to keep it')),
      );
    }
  }

  Future<void> _loadRelationships(Entity e) async {
    setState(() => _relLoading = true);
    try {
      final detail = await ApiClient.instance.getEntity(e.id);
      final counterpartIds = <String>{};
      for (final r in detail.relationships) {
        counterpartIds.add(r.sourceId == e.id ? r.targetId : r.sourceId);
      }
      await Future.wait(counterpartIds.map((id) async {
        try {
          final c = await ApiClient.instance.getEntity(id);
          _refs[c.id] = EntityRef(
            id: c.id,
            slug: c.slug,
            type: c.type,
            name: c.name,
            status: c.status,
            summary: c.summary,
          );
        } catch (_) {}
      }));
      if (mounted) setState(() => _relationships = detail.relationships);
    } finally {
      if (mounted) setState(() => _relLoading = false);
    }
  }

  Map<String, dynamic> _body() => {
        'name': _name.text.trim(),
        'type': _type,
        'status': _status,
        'summary': _summary.text.trim(),
        'content': _content.text,
        'metadata': {
          ..._metadata,
          if (_tags.isNotEmpty) 'tags': _tags,
        },
        if (_parentId != null) 'parent_id': _parentId,
      };

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      _toast('Give it a name first.');
      return;
    }
    setState(() => _saving = true);
    try {
      final api = ApiClient.instance;
      if (widget.isCreate) {
        await api.createEntity(_body());
      } else {
        await api.updateEntity(widget.entity!.id, _body());
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _saving = false);
      _toast('$e');
    }
  }

  Future<void> _pickParent() async {
    final e = await showEntityPicker(context, title: 'Choose a parent');
    if (e != null && e.id != widget.entity?.id) {
      setState(() {
        _parentId = e.id;
        _parentName = e.name;
      });
    }
  }

  Future<void> _addRelationship() async {
    final target = await showEntityPicker(context, title: 'Relationship target');
    if (target == null || !mounted) return;
    final type = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Relationship type'),
        children: relationshipTypes
            .map((t) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, t),
                  child: Text(relationshipLabels[t] ?? t,
                      style: const TextStyle(fontFamily: KronicleTheme.ui)),
                ))
            .toList(),
      ),
    );
    if (type == null) return;
    try {
      await ApiClient.instance.createRelationship({
        'source_id': widget.entity!.id,
        'target_id': target.id,
        'type': type,
      });
      _refs[target.id] = EntityRef(
        id: target.id,
        slug: target.slug,
        type: target.type,
        name: target.name,
        status: target.status,
        summary: target.summary,
      );
      await _loadRelationships(widget.entity!);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<void> _removeRelationship(Relationship r) async {
    try {
      await ApiClient.instance.deleteRelationship(r.id);
      await _loadRelationships(widget.entity!);
    } catch (e) {
      _toast('$e');
    }
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = KronicleColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isCreate ? 'New entity' : 'Edit'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          _label('Name'),
          TextField(
            controller: _name,
            decoration: const InputDecoration(hintText: 'Name'),
            style: const TextStyle(
              fontFamily: KronicleTheme.ui,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Dropdown(
                  label: 'Type',
                  value: _type,
                  items: {for (final t in entityTypes) t: typeLabels[t]!},
                  onChanged: (v) => setState(() => _type = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Dropdown(
                  label: 'Status',
                  value: _status,
                  items: {for (final s in statuses) s: statusLabels[s]!},
                  onChanged: (v) => setState(() => _status = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _label('Summary'),
          TextField(
            controller: _summary,
            maxLines: 2,
            decoration: const InputDecoration(hintText: 'A sentence or two'),
            style: const TextStyle(fontFamily: KronicleTheme.ui),
          ),
          const SizedBox(height: 16),
          _label('Content'),
          TextField(
            controller: _content,
            maxLines: null,
            minLines: 10,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              hintText: 'Write in Markdown. Link with [[slug]].',
              alignLabelWithHint: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colors.line),
              ),
            ),
            style: const TextStyle(
              fontFamily: KronicleTheme.editor,
              fontSize: 15,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          _label('Tags'),
          _TagsField(
            tags: _tags,
            onChanged: (t) => setState(() => _tags = t),
          ),
          const SizedBox(height: 16),
          _label('Parent'),
          OutlinedButton.icon(
            onPressed: _pickParent,
            icon: const Icon(Icons.account_tree_outlined, size: 18),
            label: Text(
              _parentName ?? (_parentId != null ? 'Linked' : 'None — tap to nest'),
            ),
          ),
          if (_parentId != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() {
                  _parentId = null;
                  _parentName = null;
                }),
                child: const Text('Clear parent'),
              ),
            ),

          // Relationships only once the entity exists (it's the source row).
          if (!widget.isCreate) ...[
            const SizedBox(height: 24),
            SectionLabel(
              'Relationships',
              trailing: TextButton.icon(
                onPressed: _addRelationship,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
              ),
            ),
            if (_relLoading)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_relationships.isEmpty)
              Text(
                'No relationships yet.',
                style: TextStyle(
                  fontFamily: KronicleTheme.ui,
                  color: colors.inkFaint,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              ..._relationships.map((r) => _RelRow(
                    relationship: r,
                    entityId: widget.entity!.id,
                    ref: _refs[r.sourceId == widget.entity!.id ? r.targetId : r.sourceId],
                    onRemove: () => _removeRelationship(r),
                  )),
          ],
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          t.toUpperCase(),
          style: TextStyle(
            fontFamily: KronicleTheme.ui,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: KronicleColors.of(context).inkFaint,
          ),
        ),
      );
}

class _Dropdown extends StatelessWidget {
  final String label;
  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;
  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: KronicleTheme.ui,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: KronicleColors.of(context).inkFaint,
            ),
          ),
        ),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
          style: TextStyle(
            fontFamily: KronicleTheme.ui,
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          items: items.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }
}

class _TagsField extends StatefulWidget {
  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  const _TagsField({required this.tags, required this.onChanged});

  @override
  State<_TagsField> createState() => _TagsFieldState();
}

class _TagsFieldState extends State<_TagsField> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add(String v) {
    final t = v.trim();
    if (t.isEmpty || widget.tags.contains(t)) {
      _input.clear();
      return;
    }
    widget.onChanged([...widget.tags, t]);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.tags
                  .map((t) => Chip(
                        label: Text(t),
                        onDeleted: () => widget
                            .onChanged(widget.tags.where((x) => x != t).toList()),
                      ))
                  .toList(),
            ),
          ),
        TextField(
          controller: _input,
          onSubmitted: _add,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: 'Add a tag and press enter',
            prefixIcon: Icon(Icons.tag, size: 18),
            isDense: true,
          ),
          style: const TextStyle(fontFamily: KronicleTheme.ui),
        ),
      ],
    );
  }
}

class _RelRow extends StatelessWidget {
  final Relationship relationship;
  final String entityId;
  final EntityRef? ref;
  final VoidCallback onRemove;
  const _RelRow({
    required this.relationship,
    required this.entityId,
    required this.ref,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final outgoing = relationship.sourceId == entityId;
    final verb = outgoing
        ? (relationshipLabels[relationship.type] ?? relationship.type)
        : (relationshipInverseLabels[relationship.type] ?? relationship.type);
    final colors = KronicleColors.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        ref?.name ?? '(unknown)',
        style: const TextStyle(
            fontFamily: KronicleTheme.ui, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        verb,
        style: TextStyle(fontFamily: KronicleTheme.ui, color: colors.inkMuted),
      ),
      trailing: IconButton(
        icon: Icon(Icons.close, size: 18, color: colors.inkFaint),
        onPressed: onRemove,
      ),
    );
  }
}
