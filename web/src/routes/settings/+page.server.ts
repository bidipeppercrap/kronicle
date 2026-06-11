import { apiGet } from '$lib/server/api';
import type { AiSettings } from '$lib/types';
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ fetch }) => {
	const ai = await apiGet<AiSettings>(fetch, '/settings/ai');
	return { ai };
};
