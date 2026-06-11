import { apiGet, apiSend } from '$lib/server/api';
import type { Diagnostics, Entity, ListResponse } from '$lib/types';
import { fail } from '@sveltejs/kit';
import type { Actions, PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ fetch }) => {
	const [stubs, recent, drafts, canon, all, report] = await Promise.all([
		apiGet<ListResponse<Entity>>(fetch, '/entities?status=stub&limit=8'),
		apiGet<ListResponse<Entity>>(fetch, '/entities?limit=8'),
		apiGet<ListResponse<Entity>>(fetch, '/entities?status=draft&limit=1'),
		apiGet<ListResponse<Entity>>(fetch, '/entities?status=canon&limit=1'),
		apiGet<ListResponse<Entity>>(fetch, '/entities?limit=1'),
		apiGet<Diagnostics>(fetch, '/diagnostics')
	]);

	return {
		stubs: stubs.items,
		recent: recent.items,
		counts: {
			stub: stubs.total,
			draft: drafts.total,
			canon: canon.total,
			total: all.total
		},
		health: {
			brokenLinks: report.broken_links.length,
			orphans: report.orphans.length,
			staleStubs: report.stale_stubs.length
		}
	};
};

export const actions: Actions = {
	capture: async ({ request, fetch }) => {
		const form = await request.formData();
		const name = String(form.get('name') ?? '').trim();
		const note = String(form.get('note') ?? '').trim();
		if (!name) return fail(400, { error: 'Give the idea a name first.' });

		const res = await apiSend<Entity>(fetch, 'POST', '/entities', {
			name,
			...(note ? { summary: note } : {})
		});
		if (!res.ok) return fail(res.status, { error: res.message ?? 'Capture failed.' });
		return { captured: res.data };
	}
};
