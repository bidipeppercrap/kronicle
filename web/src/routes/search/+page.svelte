<script lang="ts">
	import { goto } from '$app/navigation';
	import EntityRow from '$lib/components/EntityRow.svelte';
	import TypeIcon from '$lib/components/TypeIcon.svelte';
	import { ENTITY_TYPES, TYPE_PLURALS, type Entity, type EntityType } from '$lib/types';
	import { Search } from '@lucide/svelte';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	let query = $state(data.q);
	$effect(() => {
		query = data.q;
	});

	let searchTimer: ReturnType<typeof setTimeout> | undefined;

	function navigate() {
		clearTimeout(searchTimer);
		const q = query.trim();
		if (q === data.q) return;
		goto(q ? `/search?q=${encodeURIComponent(q)}` : '/search', { keepFocus: true });
	}

	function onInput() {
		clearTimeout(searchTimer);
		searchTimer = setTimeout(navigate, 300);
	}

	const grouped = $derived(
		ENTITY_TYPES.map((type: EntityType) => ({
			type,
			items: data.items.filter((e: Entity) => e.type === type)
		})).filter((g) => g.items.length > 0)
	);
</script>

<svelte:head>
	<title>{data.q ? `“${data.q}” · ` : ''}Search · Kronicle</title>
</svelte:head>

<div class="mx-auto w-full max-w-3xl px-4 py-8 sm:px-6 md:py-12">
	<form
		onsubmit={(e) => {
			e.preventDefault();
			navigate();
		}}
		class="flex items-center gap-3 rounded-xl border border-line bg-surface px-4 shadow-sm focus-within:border-accent"
	>
		<Search class="size-5 shrink-0 text-ink-faint" />
		<!-- svelte-ignore a11y_autofocus -->
		<input
			bind:value={query}
			oninput={onInput}
			autofocus
			placeholder="Search names, summaries, and prose…"
			class="min-w-0 flex-1 bg-transparent py-4 font-prose text-lg text-ink outline-none placeholder:text-ink-faint"
		/>
		<button
			type="submit"
			class="my-2 shrink-0 rounded-lg bg-accent px-3.5 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90"
		>
			Search
		</button>
	</form>

	{#if data.q}
		<p class="mt-4 px-1 text-sm text-ink-muted">
			{data.total}
			{data.total === 1 ? 'result' : 'results'} for
			<span class="font-prose italic">“{data.q}”</span>
		</p>

		{#each grouped as group (group.type)}
			<section class="mt-8">
				<h2 class="mb-2 flex items-center gap-2 px-3 text-xs font-medium tracking-wider text-ink-faint uppercase">
					<TypeIcon type={group.type} class="size-3.5" />
					{TYPE_PLURALS[group.type]}
					<span class="text-ink-faint/70">· {group.items.length}</span>
				</h2>
				<div class="flex flex-col">
					{#each group.items as entity (entity.id)}
						<EntityRow {entity} showType={false} />
					{/each}
				</div>
			</section>
		{:else}
			<div class="py-16 text-center">
				<p class="font-prose text-lg text-ink-muted italic">No matches in the vault.</p>
				<p class="mt-1 text-sm text-ink-faint">Search looks across names, summaries, and full prose.</p>
			</div>
		{/each}
	{/if}
</div>
