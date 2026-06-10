import { Marked } from 'marked';

/**
 * Markdown renderer with [[wikilink]] support. Wikilinks are render-only
 * (DESIGN.md): `[[slug]]` / `[[slug|display]]` become links to the entity
 * detail view and never create relationship rows.
 */

const WIKILINK = /^\[\[([a-z0-9][a-z0-9-]*)(?:\|([^\]\n]+))?\]\]/;

function escapeHtml(s: string): string {
	return s
		.replaceAll('&', '&amp;')
		.replaceAll('<', '&lt;')
		.replaceAll('>', '&gt;')
		.replaceAll('"', '&quot;');
}

interface WikilinkToken {
	type: 'wikilink';
	raw: string;
	slug: string;
	display: string | null;
}

const marked = new Marked({
	gfm: true,
	breaks: false,
	extensions: [
		{
			name: 'wikilink',
			level: 'inline',
			start(src: string) {
				const i = src.indexOf('[[');
				return i < 0 ? undefined : i;
			},
			tokenizer(src: string): WikilinkToken | undefined {
				const m = WIKILINK.exec(src);
				if (!m) return undefined;
				return { type: 'wikilink', raw: m[0], slug: m[1], display: m[2] ?? null };
			},
			renderer(token) {
				const t = token as WikilinkToken;
				const text = escapeHtml(t.display ?? t.slug.replaceAll('-', ' '));
				return `<a class="wikilink" href="/entities/${t.slug}">${text}</a>`;
			}
		}
	]
});

export function renderMarkdown(content: string): string {
	return marked.parse(content, { async: false });
}

/** Slugs referenced via [[wikilinks]] in a Markdown string, deduplicated. */
export function extractWikilinks(content: string): string[] {
	const out = new Set<string>();
	for (const m of content.matchAll(/\[\[([a-z0-9][a-z0-9-]*)(?:\|[^\]\n]+)?\]\]/g)) {
		out.add(m[1]);
	}
	return [...out];
}
