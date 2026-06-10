export interface Toast {
	id: number;
	text: string;
	kind: 'ok' | 'err';
	href?: string;
}

let nextId = 0;

export const toasts = $state<Toast[]>([]);

export function toast(text: string, kind: Toast['kind'] = 'ok', href?: string) {
	const id = nextId++;
	toasts.push({ id, text, kind, href });
	setTimeout(() => {
		const i = toasts.findIndex((t) => t.id === id);
		if (i >= 0) toasts.splice(i, 1);
	}, 4000);
}
