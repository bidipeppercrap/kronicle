import 'package:flutter/material.dart';

import '../api/models.dart';
import '../nav.dart';
import '../theme/theme.dart';
import 'status_chip.dart';

/// A flat list row (no shadow, hairline-separated by the surrounding list).
/// Used across Home, List, Search, backlinks, and relationships.
class EntityTile extends StatelessWidget {
  final String idOrSlug;
  final String name;
  final String type;
  final String status;
  final String summary;

  /// Optional edge label shown above the name ("born in", "child of", …).
  final String? relationLabel;
  final VoidCallback? onTap;

  const EntityTile({
    super.key,
    required this.idOrSlug,
    required this.name,
    required this.type,
    required this.status,
    required this.summary,
    this.relationLabel,
    this.onTap,
  });

  factory EntityTile.fromEntity(Entity e, {String? relationLabel}) => EntityTile(
        idOrSlug: e.slug,
        name: e.name,
        type: e.type,
        status: e.status,
        summary: e.summary,
        relationLabel: relationLabel,
      );

  factory EntityTile.fromRef(EntityRef e, {String? relationLabel}) => EntityTile(
        idOrSlug: e.slug,
        name: e.name,
        type: e.type,
        status: e.status,
        summary: e.summary,
        relationLabel: relationLabel,
      );

  @override
  Widget build(BuildContext context) {
    final colors = KronicleColors.of(context);
    return InkWell(
      onTap: onTap ?? () => openEntity(idOrSlug),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (relationLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  relationLabel!,
                  style: TextStyle(
                    fontFamily: KronicleTheme.ui,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    color: colors.inkFaint,
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: KronicleTheme.ui,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(status, dense: true),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              summary.isNotEmpty ? summary : (typeLabels[type] ?? type),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: KronicleTheme.ui,
                fontSize: 13,
                height: 1.4,
                color: colors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
