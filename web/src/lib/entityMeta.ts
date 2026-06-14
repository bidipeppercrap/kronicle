import {
	BookMarked,
	FileText,
	MapPin,
	Milestone,
	PawPrint,
	ScrollText,
	Shield,
	Sparkles,
	User,
	type Icon as IconType
} from '@lucide/svelte';
import type { EntityType, Status } from './types';

export const TYPE_ICONS: Record<EntityType, typeof IconType> = {
	character: User,
	creature: PawPrint,
	location: MapPin,
	faction: Shield,
	lore: ScrollText,
	story: BookMarked,
	chapter: FileText,
	event: Milestone,
	ability: Sparkles
};

/** Tailwind classes per status — colors defined in app.css. */
export const STATUS_TEXT: Record<Status, string> = {
	stub: 'text-status-stub',
	draft: 'text-status-draft',
	canon: 'text-status-canon',
	rejected: 'text-status-rejected'
};

export const STATUS_BADGE: Record<Status, string> = {
	stub: 'text-status-stub border-status-stub/40 bg-status-stub/10',
	draft: 'text-status-draft border-status-draft/40 bg-status-draft/10',
	canon: 'text-status-canon border-status-canon/40 bg-status-canon/10',
	rejected: 'text-status-rejected border-status-rejected/40 bg-status-rejected/10'
};

/** Conventional metadata fields per type (DESIGN.md) — offered as quick-add chips. */
export const METADATA_SUGGESTIONS: Record<EntityType, string[]> = {
	character: ['gender', 'species', 'age', 'is_npc'],
	creature: ['category', 'habitat', 'diet', 'danger'],
	location: ['location_type', 'climate', 'population'],
	faction: ['category', 'member_count'],
	lore: ['category', 'era'],
	story: ['chapter_count', 'is_complete'],
	chapter: ['order'],
	event: ['date', 'era', 'order_index', 'precision'],
	ability: ['principle', 'category', 'range']
};

/**
 * Markdown skeletons pre-filled when an entity is created through the full
 * form (and offered in the editor when the page is still blank). Headings
 * prompt what to write; delete what doesn't apply. Chapters get none —
 * they're prose, not sheets. Quick capture never sees these: stubs stay bare.
 */
export const CONTENT_TEMPLATES: Record<EntityType, string> = {
	character: ['## Appearance', '## Personality', '## Backstory', '## Abilities & Principle']
		.join('\n\n\n')
		.concat('\n'),
	creature: ['## Description', '## Habitat & Range', '## Behavior', '## Ecology & Uses']
		.join('\n\n\n')
		.concat('\n'),
	location: ['## Geography', '## Notable Places', '## Residents & Factions', '## History']
		.join('\n\n\n')
		.concat('\n'),
	faction: ['## Purpose', '## Members', '## Holdings', '## History'].join('\n\n\n').concat('\n'),
	lore: ['## Overview', '## Workings', '## History'].join('\n\n\n').concat('\n'),
	story: ['## Premise', '## Arc', '## Open Threads'].join('\n\n\n').concat('\n'),
	chapter: '',
	event: ['## What Happened', '## Who Was Involved', '## Consequences']
		.join('\n\n\n')
		.concat('\n'),
	ability: ['## Mechanics', '## Origin', '## Limitations'].join('\n\n\n').concat('\n')
};

export const STATUS_DOT: Record<Status, string> = {
	stub: 'bg-status-stub',
	draft: 'bg-status-draft',
	canon: 'bg-status-canon',
	rejected: 'bg-status-rejected'
};
