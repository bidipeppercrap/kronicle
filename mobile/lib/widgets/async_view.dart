import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Standard loading / error / empty handling around a Future, so every screen
/// renders the three states the same way. Pull-to-refresh is the caller's job
/// (it re-issues the future via setState).
class AsyncView<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(T data) builder;
  final bool Function(T data)? isEmpty;
  final String emptyMessage;
  final VoidCallback? onRetry;

  const AsyncView({
    super.key,
    required this.future,
    required this.builder,
    this.isEmpty,
    this.emptyMessage = 'Nothing here yet.',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _ErrorState(message: '${snap.error}', onRetry: onRetry);
        }
        final data = snap.data as T;
        if (isEmpty?.call(data) ?? false) {
          return _EmptyState(message: emptyMessage);
        }
        return builder(data);
      },
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const _ErrorState({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = KronicleColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, color: colors.inkFaint, size: 36),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: KronicleTheme.ui, color: colors.inkMuted),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = KronicleColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: KronicleTheme.ui,
            color: colors.inkFaint,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}

/// A thin section header used inside detail/home columns.
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final colors = KronicleColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontFamily: KronicleTheme.ui,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: colors.inkFaint,
            ),
          ),
          if (trailing != null) ...[const Spacer(), trailing!],
        ],
      ),
    );
  }
}

/// A flat card container (hairline border, tonal fill, no shadow).
class FlatCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const FlatCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    final colors = KronicleColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.line),
      ),
      padding: padding,
      child: child,
    );
  }
}

/// A list of tiles separated by hairlines, wrapped in a flat card.
class TileCard extends StatelessWidget {
  final List<Widget> tiles;
  const TileCard({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) {
    final colors = KronicleColors.of(context);
    final children = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      if (i > 0) children.add(Divider(height: 1, color: colors.line));
      children.add(tiles[i]);
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.line),
      ),
      child: Column(children: children),
    );
  }
}
