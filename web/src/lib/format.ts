const RELATIVE_UNITS: [Intl.RelativeTimeFormatUnit, number][] = [
	['year', 1000 * 60 * 60 * 24 * 365],
	['month', 1000 * 60 * 60 * 24 * 30],
	['week', 1000 * 60 * 60 * 24 * 7],
	['day', 1000 * 60 * 60 * 24],
	['hour', 1000 * 60 * 60],
	['minute', 1000 * 60]
];

const rtf = new Intl.RelativeTimeFormat('en', { numeric: 'auto', style: 'narrow' });

export function timeAgo(iso: string): string {
	const delta = new Date(iso).getTime() - Date.now();
	for (const [unit, ms] of RELATIVE_UNITS) {
		if (Math.abs(delta) >= ms) return rtf.format(Math.round(delta / ms), unit);
	}
	return 'just now';
}

export function fullDate(iso: string): string {
	return new Date(iso).toLocaleString('en-GB', {
		day: 'numeric',
		month: 'long',
		year: 'numeric',
		hour: '2-digit',
		minute: '2-digit'
	});
}

export function wordCount(text: string): number {
	const words = text.trim().match(/\S+/g);
	return words ? words.length : 0;
}

/** First ~n characters of prose, cut at a word boundary. */
export function excerpt(text: string, n = 160): string {
	const plain = text.replaceAll(/[#*_>`[\]|]/g, ' ').replaceAll(/\s+/g, ' ').trim();
	if (plain.length <= n) return plain;
	const cut = plain.slice(0, n);
	return `${cut.slice(0, Math.max(cut.lastIndexOf(' '), n - 20))}…`;
}

/** "metadata.key" → "Key", "is_npc" → "Is NPC" style labels for the metadata sidebar. */
export function metaLabel(key: string): string {
	return key
		.split('_')
		.map((w) => (w === 'npc' ? 'NPC' : w.charAt(0).toUpperCase() + w.slice(1)))
		.join(' ');
}
