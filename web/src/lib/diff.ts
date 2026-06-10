/**
 * Line-level unified diff for AI proposal cards. LCS-based — plenty at
 * personal scale, where prose runs hundreds of lines, not millions.
 */

export type DiffRow =
	| { kind: 'same' | 'add' | 'del'; text: string }
	| { kind: 'skip'; count: number };

export function unifiedDiff(before: string, after: string, context = 3): DiffRow[] {
	const a = before === '' ? [] : before.split('\n');
	const b = after === '' ? [] : after.split('\n');
	const n = a.length;
	const m = b.length;

	// Degenerate guard: beyond this, show a full replacement instead of
	// burning seconds on the DP table.
	if (n * m > 2_000_000) {
		return [
			...a.map((text) => ({ kind: 'del' as const, text })),
			...b.map((text) => ({ kind: 'add' as const, text }))
		];
	}

	const w = m + 1;
	const dp = new Uint32Array((n + 1) * w);
	for (let i = n - 1; i >= 0; i--) {
		for (let j = m - 1; j >= 0; j--) {
			dp[i * w + j] =
				a[i] === b[j]
					? dp[(i + 1) * w + j + 1] + 1
					: Math.max(dp[(i + 1) * w + j], dp[i * w + j + 1]);
		}
	}

	const ops: { kind: 'same' | 'add' | 'del'; text: string }[] = [];
	let i = 0;
	let j = 0;
	while (i < n && j < m) {
		if (a[i] === b[j]) {
			ops.push({ kind: 'same', text: a[i] });
			i++;
			j++;
		} else if (dp[(i + 1) * w + j] >= dp[i * w + j + 1]) {
			ops.push({ kind: 'del', text: a[i] });
			i++;
		} else {
			ops.push({ kind: 'add', text: b[j] });
			j++;
		}
	}
	while (i < n) ops.push({ kind: 'del', text: a[i++] });
	while (j < m) ops.push({ kind: 'add', text: b[j++] });

	// Collapse long unchanged runs to `context` lines on each side.
	const rows: DiffRow[] = [];
	let sameBuf: string[] = [];
	let seenChange = false;
	const flush = (atEnd: boolean) => {
		const head = seenChange ? Math.min(context, sameBuf.length) : 0;
		const tail = atEnd ? 0 : Math.min(context, sameBuf.length - head);
		const skipped = sameBuf.length - head - tail;
		if (skipped > 2) {
			for (let k = 0; k < head; k++) rows.push({ kind: 'same', text: sameBuf[k] });
			rows.push({ kind: 'skip', count: skipped });
			for (let k = sameBuf.length - tail; k < sameBuf.length; k++)
				rows.push({ kind: 'same', text: sameBuf[k] });
		} else {
			for (const text of sameBuf) rows.push({ kind: 'same', text });
		}
		sameBuf = [];
	};
	for (const op of ops) {
		if (op.kind === 'same') {
			sameBuf.push(op.text);
		} else {
			flush(false);
			seenChange = true;
			rows.push(op);
		}
	}
	flush(true);
	return rows;
}
