import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../nav.dart';
import '../theme/theme.dart';

final _wikilink = RegExp(r'\[\[([^\]|]+)(?:\|([^\]]+))?\]\]');

/// Turn `[[slug]]` / `[[slug|display]]` into ordinary Markdown links with a
/// `kronicle:` scheme, so flutter_markdown renders them as taps we resolve to
/// entity navigation. Wikilinks are render-only (DESIGN.md) — this creates no
/// relationship rows, just a link.
String _expandWikilinks(String md) => md.replaceAllMapped(_wikilink, (m) {
      final slug = m.group(1)!.trim();
      final display = (m.group(2) ?? m.group(1)!).trim();
      return '[$display](kronicle:$slug)';
    });

/// Rendered prose: Literata body, Quattro for code, wikilinks tappable.
class EntityMarkdown extends StatelessWidget {
  final String content;
  const EntityMarkdown(this.content, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = KronicleColors.of(context);
    final scheme = theme.colorScheme;

    final sheet = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: TextStyle(
        fontFamily: KronicleTheme.prose,
        fontSize: 16.5,
        height: 1.7,
        color: scheme.onSurface,
      ),
      h1: _heading(28, scheme.onSurface),
      h2: _heading(23, scheme.onSurface),
      h3: _heading(19, scheme.onSurface),
      h4: _heading(17, scheme.onSurface),
      blockquote: TextStyle(
        fontFamily: KronicleTheme.prose,
        fontSize: 16,
        height: 1.6,
        color: colors.inkMuted,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.line, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.only(left: 14),
      a: TextStyle(
        fontFamily: KronicleTheme.prose,
        color: colors.accentInk,
        decoration: TextDecoration.underline,
        decorationColor: colors.accentInk.withValues(alpha: 0.4),
      ),
      code: TextStyle(
        fontFamily: KronicleTheme.editor,
        fontSize: 14,
        backgroundColor: scheme.surfaceContainerHigh,
        color: scheme.onSurface,
      ),
      codeblockDecoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.line),
      ),
      listBullet: TextStyle(
        fontFamily: KronicleTheme.prose,
        fontSize: 16.5,
        height: 1.7,
        color: scheme.onSurface,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.line)),
      ),
    );

    return MarkdownBody(
      data: _expandWikilinks(content),
      styleSheet: sheet,
      selectable: true,
      onTapLink: (text, href, title) {
        if (href == null) return;
        if (href.startsWith('kronicle:')) {
          openEntity(href.substring('kronicle:'.length));
        }
        // External links are left inert — this is a personal reading view,
        // not a browser.
      },
    );
  }

  TextStyle _heading(double size, Color color) => TextStyle(
        fontFamily: KronicleTheme.prose,
        fontSize: size,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: color,
      );
}
