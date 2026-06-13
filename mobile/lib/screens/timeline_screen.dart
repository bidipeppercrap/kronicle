import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../nav.dart';
import '../theme/theme.dart';
import '../widgets/async_view.dart';
import '../widgets/status_chip.dart';

/// Chronological feed of `event` entities (DESIGN.md). Sorted by order_index on
/// the server; eras are optional grouping bands drawn over the stream. Falls
/// back to a flat stream when no eras exist.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});
  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  late Future<TimelineResult> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiClient.instance.timeline();
  }

  void _refresh() {
    ApiClient.instance.clearCache();
    setState(() => _future = ApiClient.instance.timeline());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Timeline')),
      body: AsyncView<TimelineResult>(
        future: _future,
        onRetry: _refresh,
        isEmpty: (t) => t.items.isEmpty,
        emptyMessage: 'No events yet. Create an entity of type Event to place '
            'it on the timeline.',
        builder: (data) {
          final eraName = {for (final e in data.eras) e.slug: e.name};
          final hasEras = data.eras.isNotEmpty;

          // Walk the chronologically-sorted stream, emitting an era header
          // whenever the band changes (DESIGN.md "draws era headers over the
          // stream"). Null/unknown era reads as "No era".
          final rows = <Widget>[];
          String? lastEra = '__init__';
          for (final ev in data.items) {
            final era = ev.metadata['era'] as String?;
            if (hasEras && era != lastEra) {
              lastEra = era;
              rows.add(_EraHeader(
                label: era == null ? 'No era' : (eraName[era] ?? era),
              ));
            }
            rows.add(_EventRow(event: ev));
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
              children: rows,
            ),
          );
        },
      ),
    );
  }
}

class _EraHeader extends StatelessWidget {
  final String label;
  const _EraHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = KronicleColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: KronicleTheme.ui,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: colors.accentInk,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(color: colors.line, height: 1)),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final Entity event;
  const _EventRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final colors = KronicleColors.of(context);
    final date = event.metadata['date'] as String?;
    return InkWell(
      onTap: () => openEntity(event.slug),
      borderRadius: BorderRadius.circular(10),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The spine: a dot on a vertical rule.
            Column(
              children: [
                const SizedBox(height: 5),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: colors.status(event.status),
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Container(width: 1.5, color: colors.line),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (date != null && date.isNotEmpty)
                      Text(
                        date,
                        style: TextStyle(
                          fontFamily: KronicleTheme.editor,
                          fontSize: 12,
                          color: colors.inkFaint,
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            event.name,
                            style: TextStyle(
                              fontFamily: KronicleTheme.ui,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        StatusChip(event.status, dense: true),
                      ],
                    ),
                    if (event.summary.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          event.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: KronicleTheme.ui,
                            fontSize: 13,
                            height: 1.4,
                            color: colors.inkMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
