<script lang="ts">
	import { goto } from '$app/navigation';
	import { navigating, page } from '$app/state';
	import EntityRow from '$lib/components/EntityRow.svelte';
	import TypeIcon from '$lib/components/TypeIcon.svelte';
	import { STATUS_DOT } from '$lib/entityMeta';
	import { ENTITY_TYPES, STATUSES, STATUS_LABELS, TYPE_PLURALS } from '$lib/types';
	import { ChevronLeft, ChevronRight, CirclePlus, Search, X } from '@lucide/svelte';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	let searchValue = $state(data.filters.search);
	$effect(() => {
		searchValue = data.filters.search;
	});

	// Results fade softly while a filter navigation is in flight.
	const loading = $derived(navigating.to?.url.pathname === '/entities');

	let searchTimer: ReturnType<typeof setTimeout> | undefined;

	function submitSearch() {
		clearTimeout(searchTimer);
		const next = searchValue.trim() || null;
		if (next === (data.filters.search || null)) return;
		goto(buildUrl({ q: next }), { keepFocus: true });
	}

	function onSearchInput() {
		clearTimeout(searchTimer);
		searchTimer = setTimeout(submitSearch, 300);
	}

	function buildUrl(patch: Record<string, string | null>): string {
		const params = new URLSearchParams(page.url.searchParams);
		params.delete('page'); // any filter change resets pagination
		for (const [k, v] of Object.entries(patch)) {
			if (v === null || v === '') params.delete(k);
			else params.set(k, v);
		}
		const qs = params.toString();
		return qs ? `/entities?${qs}` : '/entities';
	}

	const lastPage = $derived(Math.max(1, Math.ceil(data.total / data.pageSize)));

	function pageUrl(n: number): string {
		const params = new URLSearchParams(page.url.searchParams);
		if (n <= 1) params.delete('page');
		else params.set('page', String(n));
		const qs = params.toString();
		return qs ? `/entities?${qs}` : '/entities';
	}
</script>

<svelte:head>
	<title>Entities · Kronicle</title>
</svelte:head>

<div class="mx-auto w-full max-w-4xl px-4 py-8 sm:px-6">
	<div class="mb-6 flex flex-wrap items-center justify-between gap-3">
		<h1 class="font-prose text-2xl font-semibold tracking-tight text-ink">Entities</h1>
		<a
			href="/entities/new{data.filters.type ? `?type=${data.filters.type}` : ''}"
			class="flex items-center gap-1.5 rounded-lg border border-line bg-surface px-3 py-1.5 text-sm font-medium text-ink transition-colors hover:border-accent hover:text-accent-ink"
		>
			<CirclePlus class="size-4 text-accent" /> New
		</a>
	</div>

	<!-- Type tabs -->
	<nav
		class="scrollbar-none mb-3 flex gap-1 overflow-x-auto border-b border-line-soft pb-px"
		aria-label="Type"
	>
		<a
			href={buildUrl({ type: null })}
			class="shrink-0 rounded-t-lg border-b-2 px-3 py-2 text-sm transition-colors
			{!data.filters.type
				? 'border-accent font-medium text-accent-ink'
				: 'border-transparent text-ink-muted hover:text-ink'}"
		>
			All
		</a>
		{#each ENTITY_TYPES as type (type)}
			<a
				href={buildUrl({ type })}
				class="flex shrink-0 items-center gap-1.5 rounded-t-lg border-b-2 px-3 py-2 text-sm transition-colors
				{data.filters.type === type
					? 'border-accent font-medium text-accent-ink'
					: 'border-transparent text-ink-muted hover:text-ink'}"
			>
				<TypeIcon {type} class="size-3.5" />
				{TYPE_PLURALS[type]}
			</a>
		{/each}
	</nav>

	<!-- Status chips + search -->
	<div class="mb-5 flex flex-wrap items-center gap-2">
		{#if data.filters.tag}
			<a
				href={buildUrl({ tag: null })}
				title="Clear tag filter"
				class="flex items-center gap-1 rounded-full border border-accent bg-accent-soft px-2.5 py-1 text-xs font-medium text-accent-ink transition-colors hover:opacity-80"
			>
				#{data.filters.tag}
				<X class="size-3" />
			</a>
		{/if}
		{#each STATUSES as status (status)}
			<a
				href={buildUrl({ status: data.filters.status === status ? null : status })}
				class="flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-medium transition-colors
				{data.filters.status === status
					? 'border-accent bg-accent-soft text-accent-ink'
					: 'border-line text-ink-muted hover:border-ink-faint hover:text-ink'}"
			>
				<span class="size-1.5 rounded-full {STATUS_DOT[status]}"></span>
				{STATUS_LABELS[status]}
			</a>
		{/each}

		<form
			class="ml-auto flex min-w-44 items-center gap-2 rounded-full border border-line bg-surface px-3 py-1 focus-within:border-accent"
			onsubmit={(e) => {
				e.preventDefault();
				submitSearch();
			}}
		>
			<Search class="size-3.5 shrink-0 text-ink-faint {loading ? 'animate-pulse text-accent' : ''}" />
			<input
				bind:value={searchValue}
				oninput={onSearchInput}
				placeholder="Filter…"
				class="w-full bg-transparent py-0.5 text-sm text-ink outline-none placeholder:text-ink-faint"
			/>
		</form>
	</div>

	<div class="transition-opacity duration-300 {loading ? 'opacity-40' : 'opacity-100'}">
	{#if data.items.length}
		<p class="mb-1 px-3 text-xs text-ink-faint">
			{data.total}
			{data.total === 1 ? 'entity' : 'entities'}
			{#if data.filters.search}matching “{data.filters.search}”{/if}
		</p>
		<div class="flex flex-col">
			{#each data.items as entity (entity.id)}
				<EntityRow {entity} showType={!data.filters.type} />
			{/each}
		</div>

		{#if lastPage > 1}
			<div class="mt-6 flex items-center justify-center gap-4 text-sm">
				{#if data.page > 1}
					<a
						href={pageUrl(data.page - 1)}
						class="flex items-center gap-1 text-ink-muted hover:text-accent-ink"
					>
						<ChevronLeft class="size-4" /> Newer
					</a>
				{/if}
				<span class="text-xs text-ink-faint">page {data.page} of {lastPage}</span>
				{#if data.page < lastPage}
					<a
						href={pageUrl(data.page + 1)}
						class="flex items-center gap-1 text-ink-muted hover:text-accent-ink"
					>
						Older <ChevronRight class="size-4" />
					</a>
				{/if}
			</div>
		{/if}
	{:else}
		<div class="py-16 text-center">
			<p class="font-prose text-lg text-ink-muted italic">Nothing here yet.</p>
			<p class="mt-1 text-sm text-ink-faint">
				{#if data.filters.search || data.filters.status || data.filters.type}
					Try widening the filters.
				{:else}
					Capture an idea from the dashboard or create an entity.
				{/if}
			</p>
		</div>
	{/if}
	</div>
</div>
