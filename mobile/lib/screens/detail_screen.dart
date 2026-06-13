import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../nav.dart';
import '../state/chat_context.dart';
import '../theme/theme.dart';
import '../widgets/async_view.dart';
import '../widgets/entity_markdown.dart';
import '../widgets/entity_tile.dart';
import '../widgets/status_chip.dart';

class _DetailData {
  final EntityDetail entity;
  final List<EntityRef> backlinks;
  final List<Entity> children;
  final Map<String, EntityRef> refs;
  final EntityRef? parent;
  _DetailData({
    required this.entity,
    required this.backlinks,
    required this.children,
    required this.refs,
    required this.parent,
  });
}

/// Full read: metadata, Markdown with wikilinks, media, relationships (both
/// directions), children, and "mentioned-in" backlinks (DESIGN.md). Registers
/// the chat focus while open so the route-aware chat anchors here.
class DetailScreen extends StatefulWidget {
  final String idOrSlug;
  const DetailScreen({super.key, required this.idOrSlug});
  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late Future<_DetailData> _future;
  Object? _focusKey;

  @override
  void initState() {
    super.initState();
    _future = _load();
    // Refetch when a chat proposal lands on this (or any) entity.
    RefreshBus.instance.addListener(_onExternalChange);
  }

  @override
  void dispose() {
    RefreshBus.instance.removeListener(_onExternalChange);
    if (_focusKey != null) ChatContextModel.instance.remove(_focusKey!);
    super.dispose();
  }

  void _onExternalChange() {
    if (mounted) setState(() => _future = _load());
  }

  Future<_DetailData> _load() async {
    final api = ApiClient.instance;
    final entity = await api.getEntity(widget.idOrSlug);

    // Tell the chat what's in focus (DESIGN.md route-aware chat).
    final focus = ChatFocus.fromEntity(entity);
    if (_focusKey == null) {
      _focusKey = ChatContextModel.instance.push(focus);
    } else {
      ChatContextModel.instance.update(_focusKey!, focus);
    }

    final counterpartIds = <String>{};
    for (final r in entity.relationships) {
      counterpartIds.add(r.sourceId == entity.id ? r.targetId : r.sourceId);
    }
    if (entity.parentId != null) counterpartIds.add(entity.parentId!);

    final backlinks = await api.backlinks(entity.id);
    final children = await api.children(entity.id);
    final refs = <String, EntityRef>{};
    await Future.wait(counterpartIds.map((id) async {
      try {
        final e = await api.getEntity(id);
        refs[e.id] = EntityRef(
          id: e.id,
          slug: e.slug,
          type: e.type,
          name: e.name,
          status: e.status,
          summary: e.summary,
        );
      } catch (_) {
        // A dangling counterpart just renders without its name.
      }
    }));

    return _DetailData(
      entity: entity,
      backlinks: backlinks,
      children: children,
      refs: refs,
      parent: entity.parentId != null ? refs[entity.parentId] : null,
    );
  }

  void _reload() {
    ApiClient.instance.clearCache();
    setState(() => _future = _load());
  }

  Future<void> _setStatus(EntityDetail e, String status) async {
    try {
      await ApiClient.instance.updateEntity(e.id, {'status': status});
      _reload();
    } catch (err) {
      _toast('$err');
    }
  }

  Future<void> _delete(EntityDetail e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${e.name}?'),
        content: const Text(
          'This removes the entity, its relationships, and media. '
          'Prose is gone for good.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: KronicleColors.of(context).rejected,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiClient.instance.deleteEntity(e.id);
      if (mounted) Navigator.of(context).pop();
    } catch (err) {
      _toast('$err');
    }
  }

  void _toast(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AsyncView<_DetailData>(
        future: _future,
        onRetry: _reload,
        builder: (data) => _DetailBody(
          data: data,
          onEdit: () async {
            if (await openEditor(data.entity) == true) _reload();
          },
          onSetStatus: (s) => _setStatus(data.entity, s),
          onDelete: () => _delete(data.entity),
          onRefresh: () async => _reload(),
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  final _DetailData data;
  final VoidCallback onEdit;
  final ValueChanged<String> onSetStatus;
  final VoidCallback onDelete;
  final Future<void> Function() onRefresh;

  const _DetailBody({
    required this.data,
    required this.onEdit,
    required this.onSetStatus,
    required this.onDelete,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final e = data.entity;
    final colors = KronicleColors.of(context);

    // Relationships split by direction, with the counterpart's name resolved.
    final relTiles = <Widget>[];
    for (final r in e.relationships) {
      final outgoing = r.sourceId == e.id;
      final otherId = outgoing ? r.targetId : r.sourceId;
      final ref = data.refs[otherId];
      final verb = outgoing
          ? (relationshipLabels[r.type] ?? r.type)
          : (relationshipInverseLabels[r.type] ?? r.type);
      final label = r.label != null && r.label!.isNotEmpty
          ? '$verb · ${r.label}'
          : verb;
      if (ref != null) {
        relTiles.add(EntityTile.fromRef(ref, relationLabel: label));
      }
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: Text(e.name, overflow: TextOverflow.ellipsis),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Set status',
                icon: const Icon(Icons.flag_outlined),
                onSelected: onSetStatus,
                itemBuilder: (_) => statuses
                    .map((s) => PopupMenuItem(
                          value: s,
                          child: Row(
                            children: [
                              Icon(Icons.circle, size: 10, color: colors.status(s)),
                              const SizedBox(width: 8),
                              Text(statusLabels[s]!),
                            ],
                          ),
                        ))
                    .toList(),
              ),
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 18, color: colors.rejected),
                        const SizedBox(width: 8),
                        const Text('Delete'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
            sliver: SliverList.list(
              children: [
                // Header
                Row(
                  children: [
                    MetaChip(e.typeLabel),
                    const SizedBox(width: 8),
                    StatusChip(e.status),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  e.name,
                  style: TextStyle(
                    fontFamily: KronicleTheme.prose,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (data.parent != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: InkWell(
                      onTap: () => openEntity(data.parent!.slug),
                      child: Text(
                        '↑ in ${data.parent!.name}',
                        style: TextStyle(
                          fontFamily: KronicleTheme.ui,
                          fontSize: 13,
                          color: colors.accentInk,
                        ),
                      ),
                    ),
                  ),
                if (e.summary.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    e.summary,
                    style: TextStyle(
                      fontFamily: KronicleTheme.prose,
                      fontSize: 17,
                      height: 1.5,
                      fontStyle: FontStyle.italic,
                      color: colors.inkMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                _MetadataBlock(entity: e),

                if (e.media.isNotEmpty) ...[
                  SectionLabel('Media'),
                  _MediaGallery(media: e.media),
                  const SizedBox(height: 24),
                ],

                // Prose
                if (e.content.isNotEmpty)
                  EntityMarkdown(e.content)
                else
                  Text(
                    'No prose yet.',
                    style: TextStyle(
                      fontFamily: KronicleTheme.prose,
                      fontStyle: FontStyle.italic,
                      color: colors.inkFaint,
                    ),
                  ),

                const SizedBox(height: 28),

                if (relTiles.isNotEmpty) ...[
                  SectionLabel('Relationships'),
                  TileCard(tiles: relTiles),
                  const SizedBox(height: 24),
                ],
                if (data.children.isNotEmpty) ...[
                  SectionLabel('Contains'),
                  TileCard(
                    tiles: data.children.map(EntityTile.fromEntity).toList(),
                  ),
                  const SizedBox(height: 24),
                ],
                if (data.backlinks.isNotEmpty) ...[
                  SectionLabel('Mentioned in'),
                  TileCard(
                    tiles: data.backlinks.map(EntityTile.fromRef).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Type-specific metadata as compact rows + tags as chips. Metadata is freeform
/// JSON, so we render whatever is there (skipping tags, which get chips).
class _MetadataBlock extends StatelessWidget {
  final EntityDetail entity;
  const _MetadataBlock({required this.entity});

  @override
  Widget build(BuildContext context) {
    final colors = KronicleColors.of(context);
    final entries = entity.metadata.entries
        .where((e) => e.key != 'tags' && e.value != null && '${e.value}'.isNotEmpty)
        .toList();
    final tags = entity.tags;
    if (entries.isEmpty && tags.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: FlatCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        e.key.replaceAll('_', ' '),
                        style: TextStyle(
                          fontFamily: KronicleTheme.ui,
                          fontSize: 13,
                          color: colors.inkFaint,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${e.value}',
                        style: TextStyle(
                          fontFamily: KronicleTheme.ui,
                          fontSize: 13.5,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (tags.isNotEmpty) ...[
              if (entries.isNotEmpty) const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    tags.map((t) => MetaChip(t, icon: Icons.tag)).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MediaGallery extends StatelessWidget {
  final List<Media> media;
  const _MediaGallery({required this.media});

  @override
  Widget build(BuildContext context) {
    final api = ApiClient.instance;
    final colors = KronicleColors.of(context);
    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: media.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final m = media[i];
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 140,
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: Image.network(
                api.mediaFileUrl(m.id),
                headers: api.mediaHeaders,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Center(
                  child: Icon(Icons.broken_image_outlined, color: colors.inkFaint),
                ),
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
          );
        },
      ),
    );
  }
}
