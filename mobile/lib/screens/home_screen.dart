import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../theme/theme.dart';
import '../widgets/async_view.dart';
import '../widgets/entity_tile.dart';
import 'quick_capture.dart';
import 'settings_screen.dart';

class _HomeData {
  final List<Entity> stubs;
  final List<Entity> recent;
  final int total, stubCount, draftCount, canonCount;
  _HomeData({
    required this.stubs,
    required this.recent,
    required this.total,
    required this.stubCount,
    required this.draftCount,
    required this.canonCount,
  });
}

/// Dashboard — quick capture, stubs awaiting triage, recent, stats (DESIGN.md).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_HomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HomeData> _load() async {
    final api = ApiClient.instance;
    final results = await Future.wait([
      api.listEntities(status: 'stub', limit: 8),
      api.listEntities(limit: 8),
      api.listEntities(status: 'draft', limit: 1),
      api.listEntities(status: 'canon', limit: 1),
    ]);
    return _HomeData(
      stubs: results[0].items,
      total: results[1].total,
      recent: results[1].items,
      stubCount: results[0].total,
      draftCount: results[2].total,
      canonCount: results[3].total,
    );
  }

  void _refresh() {
    ApiClient.instance.clearCache();
    setState(() => _future = _load());
  }

  Future<void> _capture() async {
    if (await showQuickCapture(context)) _refresh();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    // Server/token may have changed — the cache was cleared on save, so reload.
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kronicle'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _capture,
        icon: const Icon(Icons.add),
        label: const Text('Capture'),
      ),
      body: AsyncView<_HomeData>(
        future: _future,
        onRetry: _refresh,
        builder: (data) => RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              _Stats(data: data),
              const SizedBox(height: 24),
              if (data.stubs.isNotEmpty) ...[
                SectionLabel('Stubs to triage'),
                TileCard(
                  tiles: data.stubs.map(EntityTile.fromEntity).toList(),
                ),
                const SizedBox(height: 24),
              ],
              SectionLabel('Recent'),
              if (data.recent.isEmpty)
                FlatCard(
                  child: Text(
                    'Nothing captured yet. Tap Capture to start your vault.',
                    style: TextStyle(
                      fontFamily: KronicleTheme.ui,
                      color: KronicleColors.of(context).inkFaint,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                )
              else
                TileCard(
                  tiles: data.recent.map(EntityTile.fromEntity).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  final _HomeData data;
  const _Stats({required this.data});

  @override
  Widget build(BuildContext context) {
    final colors = KronicleColors.of(context);
    Widget stat(String label, int value, Color color) => Expanded(
          child: Column(
            children: [
              Text(
                '$value',
                style: TextStyle(
                  fontFamily: KronicleTheme.ui,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontFamily: KronicleTheme.ui,
                  fontSize: 11.5,
                  color: colors.inkFaint,
                ),
              ),
            ],
          ),
        );

    return FlatCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Row(
        children: [
          stat('Total', data.total, Theme.of(context).colorScheme.onSurface),
          stat('Stubs', data.stubCount, colors.stub),
          stat('Drafts', data.draftCount, colors.draft),
          stat('Canon', data.canonCount, colors.canon),
        ],
      ),
    );
  }
}
