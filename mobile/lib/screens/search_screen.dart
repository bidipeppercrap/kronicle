import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../theme/theme.dart';
import '../widgets/async_view.dart';
import '../widgets/entity_tile.dart';

/// Full-text search across names, summaries, and prose, grouped by type
/// (DESIGN.md). Results are never cached — always fresh.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  Timer? _debounce;
  String _query = '';
  Future<EntityPage>? _future;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    final q = v.trim();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _query = q;
        _future = q.isEmpty ? null : ApiClient.instance.search(q);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = KronicleColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              autofocus: false,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                hintText: 'Search names, summaries, prose…',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
              style: const TextStyle(fontFamily: KronicleTheme.ui),
            ),
          ),
          Expanded(
            child: _future == null
                ? Center(
                    child: Text(
                      'Search looks across names, summaries, and full prose.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: KronicleTheme.ui,
                        color: colors.inkFaint,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                : AsyncView<EntityPage>(
                    future: _future!,
                    isEmpty: (p) => p.items.isEmpty,
                    emptyMessage: 'No matches for "$_query".',
                    builder: (page) => _GroupedResults(items: page.items),
                  ),
          ),
        ],
      ),
    );
  }
}

class _GroupedResults extends StatelessWidget {
  final List<Entity> items;
  const _GroupedResults({required this.items});

  @override
  Widget build(BuildContext context) {
    final byType = <String, List<Entity>>{};
    for (final e in items) {
      byType.putIfAbsent(e.type, () => []).add(e);
    }
    final orderedTypes =
        entityTypes.where((t) => byType.containsKey(t)).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        for (final type in orderedTypes) ...[
          SectionLabel('${typePlurals[type]} · ${byType[type]!.length}'),
          TileCard(tiles: byType[type]!.map(EntityTile.fromEntity).toList()),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}
