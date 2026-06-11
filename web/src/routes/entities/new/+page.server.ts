import { CONTENT_TEMPLATES } from '$lib/entityMeta';
import { apiSend } from '$lib/server/api';
import { ENTITY_TYPES, STATUSES, type Entity, type EntityType, type Status } from '$lib/types';
import { fail, redirect } from '@sveltejs/kit';
import type { Actions } from './$types';

export const actions: Actions = {
	default: async ({ request, fetch }) => {
		const form = await request.formData();
		const name = String(form.get('name') ?? '').trim();
		const type = String(form.get('type') ?? 'lore');
		const status = String(form.get('status') ?? 'draft');
		const summary = String(form.get('summary') ?? '').trim();
		const parentId = String(form.get('parent_id') ?? '').trim();

		if (!name) return fail(400, { error: 'A name is required.' });
		if (!ENTITY_TYPES.includes(type as EntityType)) return fail(400, { error: 'Unknown type.' });
		if (!STATUSES.includes(status as Status)) return fail(400, { error: 'Unknown status.' });

		// Pre-fill the type's heading skeleton — except for stubs, which stay
		// bare by definition (the editor offers the template at promotion time).
		const template = status === 'stub' ? '' : CONTENT_TEMPLATES[type as EntityType];

		const res = await apiSend<Entity>(fetch, 'POST', '/entities', {
			name,
			type,
			status,
			summary,
			...(template ? { content: template } : {}),
			...(parentId ? { parent_id: parentId } : {})
		});
		if (!res.ok || !res.data) {
			return fail(res.status, { error: res.message ?? 'Create failed.' });
		}

		redirect(303, `/entities/${res.data.slug}/edit`);
	}
};
