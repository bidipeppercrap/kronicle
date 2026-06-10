import { apiGet } from '$lib/server/api';
import type { Entity, ListResponse } from '$lib/types';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ fetch, url }) => {
	const q = url.searchParams.get('q')?.trim() ?? '';
	if (!q) return { q, items: [], total: 0 };

	const result = await apiGet<ListResponse<Entity>>(
		fetch,
		`/search?q=${encodeURIComponent(q)}&limit=100`
	);
	return { q, items: result.items, total: result.total };
};
