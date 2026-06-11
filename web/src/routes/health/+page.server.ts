import { apiGet } from '$lib/server/api';
import type { Diagnostics } from '$lib/types';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ fetch }) => {
	const report = await apiGet<Diagnostics>(fetch, '/diagnostics');
	return { report };
};
