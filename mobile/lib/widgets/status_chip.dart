import 'package:flutter/material.dart';

import '../api/models.dart';
import '../theme/theme.dart';

/// Small status badge — the core-loop signal, colored consistently with web
/// (stub amber, draft blue-gray, canon green-ink, rejected muted red).
class StatusChip extends StatelessWidget {
  final String status;
  final bool dense;
  const StatusChip(this.status, {super.key, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final c = KronicleColors.of(context).status(status);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text(
        statusLabels[status] ?? status,
        style: TextStyle(
          fontFamily: KronicleTheme.ui,
          fontSize: dense ? 10.5 : 11.5,
          fontWeight: FontWeight.w600,
          color: c,
        ),
      ),
    );
  }
}

/// A neutral type/era/tag pill.
class MetaChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  const MetaChip(this.label, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    final colors = KronicleColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: colors.inkFaint),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: KronicleTheme.ui,
              fontSize: 11.5,
              color: colors.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}
