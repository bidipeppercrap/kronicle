export const ENTITY_TYPES = [
	'character',
	'location',
	'faction',
	'lore',
	'story',
	'chapter',
	'event',
	'ability'
] as const;

export const STATUSES = ['stub', 'draft', 'canon', 'rejected'] as const;

export const RELATIONSHIP_TYPES = [
	'born_in',
	'resides_in',
	'member_of',
	'leader_of',
	'possesses',
	'friend_of',
	'rival_of',
	'parent_of',
	'sibling_of',
	'married_to',
	'related_to',
	'appears_in',
	'setting_of',
	'occurs_at',
	'involves',
	'depicts',
	'causes',
	'based_in'
] as const;

export type EntityType = (typeof ENTITY_TYPES)[number];
export type Status = (typeof STATUSES)[number];
export type RelationshipType = (typeof RELATIONSHIP_TYPES)[number];

export interface Entity {
	id: string;
	slug: string;
	type: EntityType;
	parent_id: string | null;
	name: string;
	status: Status;
	summary: string;
	content: string;
	metadata: Record<string, unknown>;
	created_at: string;
	updated_at: string;
}

export interface Relationship {
	id: string;
	source_id: string;
	target_id: string;
	type: RelationshipType;
	label: string | null;
	metadata: Record<string, unknown>;
	created_at: string;
}

export const MEDIA_TYPES = ['portrait', 'illustration', 'reference', 'logo'] as const;
export type MediaType = (typeof MEDIA_TYPES)[number];

export interface Media {
	id: string;
	entity_id: string;
	r2_key: string;
	media_type: string;
	alt_text: string | null;
	created_at: string;
}

export interface Revision {
	id: string;
	entity_id: string;
	content: string;
	created_at: string;
}

export interface EntityDetail extends Entity {
	relationships: Relationship[];
	media: Media[];
}

export interface Backlink {
	id: string;
	slug: string;
	type: EntityType;
	name: string;
	status: Status;
	summary: string;
}

/** Entity reference rows in the vault-health report (GET /api/diagnostics). */
export interface DiagnosticRef {
	id: string;
	slug: string;
	type: EntityType;
	name: string;
	status: Status;
	summary: string;
	updated_at: string;
}

export interface Diagnostics {
	broken_links: Array<DiagnosticRef & { missing_slug: string; count: number }>;
	orphans: DiagnosticRef[];
	stale_stubs: DiagnosticRef[];
}

export interface ListResponse<T> {
	items: T[];
	total: number;
	limit: number;
	offset: number;
}

/** Human labels for relationship verbs, read from the source side. */
export const RELATIONSHIP_LABELS: Record<RelationshipType, string> = {
	born_in: 'born in',
	resides_in: 'resides in',
	member_of: 'member of',
	leader_of: 'leader of',
	possesses: 'possesses',
	friend_of: 'friend of',
	rival_of: 'rival of',
	parent_of: 'parent of',
	sibling_of: 'sibling of',
	married_to: 'married to',
	related_to: 'related to',
	appears_in: 'appears in',
	setting_of: 'setting of',
	occurs_at: 'occurs at',
	involves: 'involves',
	depicts: 'depicts',
	causes: 'causes',
	based_in: 'based in'
};

/** Labels read from the target side ("X ← born in — Y" renders as "birthplace of Y"). */
export const RELATIONSHIP_INVERSE_LABELS: Record<RelationshipType, string> = {
	born_in: 'birthplace of',
	resides_in: 'home of',
	member_of: 'has member',
	leader_of: 'led by',
	possesses: 'wielded by',
	friend_of: 'friend of',
	rival_of: 'rival of',
	parent_of: 'child of',
	sibling_of: 'sibling of',
	married_to: 'married to',
	related_to: 'related to',
	appears_in: 'features',
	setting_of: 'set in',
	occurs_at: 'site of',
	involves: 'involved in',
	depicts: 'depicted by',
	causes: 'caused by',
	based_in: 'base of'
};

export const TYPE_LABELS: Record<EntityType, string> = {
	character: 'Character',
	location: 'Location',
	faction: 'Faction',
	lore: 'Lore',
	story: 'Story',
	chapter: 'Chapter',
	event: 'Event',
	ability: 'Ability'
};

export const TYPE_PLURALS: Record<EntityType, string> = {
	character: 'Characters',
	location: 'Locations',
	faction: 'Factions',
	lore: 'Lore',
	story: 'Stories',
	chapter: 'Chapters',
	event: 'Events',
	ability: 'Abilities'
};

export const STATUS_LABELS: Record<Status, string> = {
	stub: 'Stub',
	draft: 'Draft',
	canon: 'Canon',
	rejected: 'Rejected'
};
