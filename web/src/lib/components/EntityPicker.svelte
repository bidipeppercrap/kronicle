<script lang="ts">
	import TypeIcon from '$lib/components/TypeIcon.svelte';
	import type { Entity, EntityType, ListResponse } from '$lib/types';

	export interface PickedEntity {
		id: string;
		slug: string;
		name: string;
		type: EntityType;
	}

	let {
		selected = $bindable(null),
		placeholder = 'Find an entity…',
		type,
		exclude = []
	}: {
		selected?: PickedEntity | null;
		placeholder?: string;
		/** Restrict results to one entity type. */
		type?: EntityType;
		/** Entity ids to hide from results (e.g. self). */
		exclude?: string[];
	} = $props();

	let query = $state('');
	let results = $state<PickedEntity[]>([]);
	let open = $state(false);
	let highlighted = $state(0);
	let timer: ReturnType<typeof setTimeout> | undefined;

	function search(q: string) {
		clearTimeout(timer);
		timer = setTimeout(async () => {
			try {
				const url = q.trim()
					? `/api/search?q=${encodeURIComponent(q.trim())}${type ? `&type=${type}` : ''}&limit=10`
					: `/api/entities?limit=10${type ? `&type=${type}` : ''}`;
				const res = await fetch(url);
				const data = (await res.json()) as ListResponse<Entity>;
				results = data.items
					.filter((e) => !exclude.includes(e.id))
					.map((e) => ({ id: e.id, slug: e.slug, name: e.name, type: e.type }));
				highlighted = 0;
				open = true;
			} catch {
				results = [];
			}
		}, 150);
	}

	function pick(item: PickedEntity) {
		selected = item;
		query = '';
		open = false;
	}

	function onKeydown(e: KeyboardEvent) {
		if (!open || !results.length) return;
		if (e.key === 'ArrowDown') {
			e.preventDefault();
			highlighted = (highlighted + 1) % results.length;
		} else if (e.key === 'ArrowUp') {
			e.preventDefault();
			highlighted = (highlighted - 1 + results.length) % results.length;
		} else if (e.key === 'Enter') {
			e.preventDefault();
			pick(results[highlighted]);
		} else if (e.key === 'Escape') {
			open = false;
		}
	}
</script>

<div class="relative">
	{#if selected}
		<div
			class="flex items-center gap-2 rounded-lg border border-line bg-surface px-2.5 py-1.5 text-sm"
		>
			<TypeIcon type={selected.type} class="size-3.5 shrink-0 text-ink-faint" />
			<span class="min-w-0 flex-1 truncate text-ink">{selected.name}</span>
			<button
				type="button"
				class="text-ink-faint transition-colors hover:text-status-rejected"
				onclick={() => (selected = null)}
				aria-label="Clear selection"
			>
				×
			</button>
		</div>
	{:else}
		<input
			bind:value={query}
			{placeholder}
			oninput={() => search(query)}
			onfocus={() => search(query)}
			onkeydown={onKeydown}
			onblur={() => setTimeout(() => (open = false), 150)}
			class="w-full rounded-lg border border-line bg-surface px-2.5 py-1.5 text-sm text-ink outline-none placeholder:text-ink-faint focus:border-accent"
		/>
		{#if open && results.length}
			<ul
				class="absolute z-30 mt-1 max-h-56 w-full overflow-y-auto rounded-lg border border-line bg-surface py-1 shadow-lg"
				role="listbox"
			>
				{#each results as item, i (item.id)}
					<li role="option" aria-selected={i === highlighted}>
						<button
							type="button"
							class="flex w-full items-center gap-2 px-2.5 py-1.5 text-left text-sm
							{i === highlighted ? 'bg-accent-soft text-accent-ink' : 'text-ink'}"
							onmouseenter={() => (highlighted = i)}
							onmousedown={(e) => {
								e.preventDefault();
								pick(item);
							}}
						>
							<TypeIcon type={item.type} class="size-3.5 shrink-0 text-ink-faint" />
							<span class="min-w-0 flex-1 truncate">{item.name}</span>
							<span class="font-mono text-[0.625rem] text-ink-faint">{item.slug}</span>
						</button>
					</li>
				{/each}
			</ul>
		{/if}
	{/if}
</div>
