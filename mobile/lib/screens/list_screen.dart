import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../nav.dart';
import '../theme/theme.dart';
import '../widgets/async_view.dart';
import '../widgets/entity_tile.dart';

/// Entity list with type tabs, status filter, and inline search (DESIGN.md).
class ListScreen extends StatefulWidget {
  const ListScreen({super.key});
  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  String? _type;
  String? _status;
  String _search = '';
  Timer? _debounce;
  late Future<EntityPage> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<EntityPage> _load() => ApiClient.instance.listEntities(
        type: _type,
        status: _status,
        search: _search.isEmpty ? null : _search,
        limit: 100,
      );

  void _reload() => setState(() => _future = _load());

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _search = v.trim();
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = KronicleColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Entities'),
        actions: [
          IconButton(
            tooltip: 'New entity',
            icon: const Icon(Icons.add),
            onPressed: () async {
              if (await openNewEntity(type: _type) == true) _reload();
            },
          ),
          PopupMenuButton<String?>(
            tooltip: 'Filter by status',
            icon: Icon(
              Icons.filter_list,
              color: _status == null ? null : colors.accentInk,
            ),
            onSelected: (v) {
              _status = v;
              _reload();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('All statuses')),
              ...statuses.map(
                (s) => PopupMenuItem(value: s, child: Text(statusLabels[s]!)),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              onChanged: _onSearch,
              decoration: const InputDecoration(
                hintText: 'Search names, summaries, prose…',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
              ),
              style: const TextStyle(fontFamily: KronicleTheme.ui),
            ),
          ),
          _TypeTabs(
            selected: _type,
            onSelect: (t) {
              _type = t;
              _reload();
            },
          ),
          if (_status != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(
                  'Filtered: ${statusLabels[_status]}',
                  style: TextStyle(
                    fontFamily: KronicleTheme.ui,
                    fontSize: 12,
                    color: colors.accentInk,
                  ),
                ),
              ),
            ),
          Expanded(
            child: AsyncView<EntityPage>(
              future: _future,
              onRetry: _reload,
              isEmpty: (p) => p.items.isEmpty,
              emptyMessage: 'No entities match these filters.',
              builder: (page) => RefreshIndicator(
                onRefresh: () async {
                  ApiClient.instance.clearCache();
                  _reload();
                },
                child: ListView.separated(
                  // Full-bleed rows (no side padding) so each tile's tap splash
                  // runs the full width of the screen; EntityTile keeps its own
                  // inner padding for the text.
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
                  itemCount: page.items.length + (page.total > page.items.length ? 1 : 0),
                  separatorBuilder: (_, _) => Divider(height: 1, color: colors.line),
                  itemBuilder: (_, i) {
                    if (i >= page.items.length) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: Text(
                            'Showing ${page.items.length} of ${page.total}',
                            style: TextStyle(
                              fontFamily: KronicleTheme.ui,
                              fontSize: 12,
                              color: colors.inkFaint,
                            ),
                          ),
                        ),
                      );
                    }
                    return EntityTile.fromEntity(page.items[i]);
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeTabs extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onSelect;
  const _TypeTabs({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final entries = <(String?, String)>[
      (null, 'All'),
      ...entityTypes.map((t) => (t, typePlurals[t]!)),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (value, label) = entries[i];
          final sel = value == selected;
          return ChoiceChip(
            label: Text(label),
            selected: sel,
            showCheckmark: false,
            onSelected: (_) => onSelect(value),
          );
        },
      ),
    );
  }
}
