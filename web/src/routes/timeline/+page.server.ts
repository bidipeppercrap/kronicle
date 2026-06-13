import { apiGet } from '$lib/server/api';
import { STATUSES, type Status, type TimelineResponse } from '$lib/types';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ fetch, url }) => {
	const statusParam = url.searchParams.get('status');
	const eraParam = url.searchParams.get('era')?.trim() ?? '';

	// The timeline is the canon view by default (DESIGN.md); ?status=all widens
	// it to every status, and a specific status narrows it.
	const status: Status | null =
		statusParam === 'all'
			? null
			: STATUSES.includes(statusParam as Status)
				? (statusParam as Status)
				: 'canon';

	const params = new URLSearchParams();
	if (status) params.set('status', status);
	if (eraParam) params.set('era', eraParam);
	const qs = params.toString();

	const data = await apiGet<TimelineResponse>(fetch, `/timeline${qs ? `?${qs}` : ''}`);

	return {
		items: data.items,
		eras: data.eras,
		filters: { status, era: eraParam || null }
	};
};
