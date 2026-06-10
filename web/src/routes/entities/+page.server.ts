import { apiGet } from '$lib/server/api';
import {
	ENTITY_TYPES,
	STATUSES,
	type Entity,
	type EntityType,
	type ListResponse,
	type Status
} from '$lib/types';
import type { PageServerLoad } from './$types';

const PAGE_SIZE = 30;

export const load: PageServerLoad = async ({ fetch, url }) => {
	const typeParam = url.searchParams.get('type');
	const statusParam = url.searchParams.get('status');
	const search = url.searchParams.get('q')?.trim() ?? '';
	const pageParam = Number(url.searchParams.get('page') ?? '1');

	const type = ENTITY_TYPES.includes(typeParam as EntityType) ? (typeParam as EntityType) : null;
	const status = STATUSES.includes(statusParam as Status) ? (statusParam as Status) : null;
	const page = Number.isInteger(pageParam) && pageParam > 0 ? pageParam : 1;

	const params = new URLSearchParams({
		limit: String(PAGE_SIZE),
		offset: String((page - 1) * PAGE_SIZE)
	});
	if (type) params.set('type', type);
	if (status) params.set('status', status);
	if (search) params.set('search', search);

	const list = await apiGet<ListResponse<Entity>>(fetch, `/entities?${params}`);

	return {
		items: list.items,
		total: list.total,
		page,
		pageSize: PAGE_SIZE,
		filters: { type, status, search }
	};
};
