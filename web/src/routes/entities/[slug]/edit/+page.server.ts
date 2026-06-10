import { apiGet } from '$lib/server/api';
import type { EntityDetail, EntityType, Status } from '$lib/types';
import type { PageServerLoad } from './$types';

export interface EntityRef {
	id: string;
	slug: string;
	name: string;
	type: EntityType;
	status: Status;
}

export const load: PageServerLoad = async ({ fetch, params }) => {
	const entity = await apiGet<EntityDetail>(fetch, `/entities/${params.slug}`);

	const counterpartIds = new Set<string>();
	for (const rel of entity.relationships) {
		counterpartIds.add(rel.source_id === entity.id ? rel.target_id : rel.source_id);
	}
	if (entity.parent_id) counterpartIds.add(entity.parent_id);

	const counterparts = await Promise.all(
		[...counterpartIds].map((id) =>
			apiGet<EntityDetail>(fetch, `/entities/${id}`).catch(() => null)
		)
	);

	const refs: Record<string, EntityRef> = {};
	for (const e of counterparts) {
		if (e) refs[e.id] = { id: e.id, slug: e.slug, name: e.name, type: e.type, status: e.status };
	}

	return { entity, refs };
};
