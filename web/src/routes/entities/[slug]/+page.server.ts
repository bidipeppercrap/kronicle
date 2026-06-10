import { renderMarkdown } from '$lib/markdown';
import { apiGet, apiSend } from '$lib/server/api';
import {
	STATUSES,
	type Backlink,
	type Entity,
	type EntityDetail,
	type ListResponse,
	type Status
} from '$lib/types';
import { fail } from '@sveltejs/kit';
import type { Actions, PageServerLoad } from './$types';

/** Light reference to a related entity, for rendering relationship rows. */
export interface EntityRef {
	id: string;
	slug: string;
	name: string;
	type: Entity['type'];
	status: Status;
}

export const load: PageServerLoad = async ({ fetch, params }) => {
	const entity = await apiGet<EntityDetail>(fetch, `/entities/${params.slug}`);

	const counterpartIds = new Set<string>();
	for (const rel of entity.relationships) {
		counterpartIds.add(rel.source_id === entity.id ? rel.target_id : rel.source_id);
	}
	if (entity.parent_id) counterpartIds.add(entity.parent_id);

	const [backlinks, children, ...counterparts] = await Promise.all([
		apiGet<Backlink[]>(fetch, `/entities/${entity.id}/backlinks`),
		apiGet<ListResponse<Entity>>(fetch, `/entities?parent_id=${entity.id}&limit=100`),
		...[...counterpartIds].map((id) =>
			apiGet<EntityDetail>(fetch, `/entities/${id}`).catch(() => null)
		)
	]);

	const refs: Record<string, EntityRef> = {};
	for (const e of counterparts) {
		if (e) refs[e.id] = { id: e.id, slug: e.slug, name: e.name, type: e.type, status: e.status };
	}

	return {
		entity,
		html: entity.content ? renderMarkdown(entity.content) : '',
		backlinks,
		children: children.items,
		refs,
		parent: entity.parent_id ? (refs[entity.parent_id] ?? null) : null
	};
};

export const actions: Actions = {
	setStatus: async ({ request, fetch, params }) => {
		const form = await request.formData();
		const status = String(form.get('status') ?? '');
		if (!STATUSES.includes(status as Status)) {
			return fail(400, { error: 'Unknown status.' });
		}
		const res = await apiSend<Entity>(fetch, 'PUT', `/entities/${params.slug}`, { status });
		if (!res.ok) return fail(res.status, { error: res.message ?? 'Status change failed.' });
		return { updated: true };
	}
};
