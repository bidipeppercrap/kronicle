<script lang="ts">
	import { page } from '$app/state';
	import StatusBadge from '$lib/components/StatusBadge.svelte';
	import { STATUS_DOT } from '$lib/entityMeta';
	import { STATUSES, STATUS_LABELS, type Entity, type EraRef } from '$lib/types';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	type Band = { slug: string | null; name: string; events: Entity[] };

	const eraName = $derived(new Map<string, string>(data.eras.map((e: EraRef) => [e.slug, e.name])));

	// Walk the already-chronological stream; open a new band whenever the era
	// changes. Era-less runs become a "No era" band. Events keep their order —
	// grouping is a header drawn over the stream, never a re-sort.
	const bands = $derived.by(() => {
		const out: Band[] = [];
		for (const ev of data.items) {
			const slug = (ev.metadata?.era as string | undefined) ?? null;
			const last = out.at(-1);
			if (!last || last.slug !== slug) {
				out.push({
					slug,
					name: slug ? (eraName.get(slug) ?? slug) : 'No era',
					events: [ev]
				});
			} else {
				last.events.push(ev);
			}
		}
		return out;
	});

	// No eras anywhere → drop the band chrome; it's a plain chronological stream.
	const flat = $derived(bands.length <= 1 && bands.every((b) => b.slug === null));

	function buildUrl(patch: Record<string, string | null>): string {
		const params = new URLSearchParams(page.url.searchParams);
		for (const [k, v] of Object.entries(patch)) {
			if (v === null) params.delete(k);
			else params.set(k, v);
		}
		const qs = params.toString();
		return qs ? `/timeline?${qs}` : '/timeline';
	}

	function dateLabel(ev: Entity): string | null {
		const d = ev.metadata?.date;
		return typeof d === 'string' && d.trim() ? d.trim() : null;
	}
</script>

<svelte:head>
	<title>Timeline · Kronicle</title>
</svelte:head>

<div class="mx-auto w-full max-w-3xl px-4 py-8 sm:px-6">
	<div class="mb-5 flex flex-wrap items-center justify-between gap-3">
		<h1 class="font-prose text-2xl font-semibold tracking-tight text-ink">Timeline</h1>
	</div>

	<!-- Status filter — canon by default, the writer's working view -->
	<div class="mb-3 flex flex-wrap items-center gap-2">
		<a
			href={buildUrl({ status: data.filters.status === null ? null : 'all' })}
			class="flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-medium transition-colors
			{data.filters.status === null
				? 'border-accent bg-accent-soft text-accent-ink'
				: 'border-line text-ink-muted hover:border-ink-faint hover:text-ink'}"
		>
			All
		</a>
		{#each STATUSES as status (status)}
			<a
				href={buildUrl({ status })}
				class="flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-medium transition-colors
				{data.filters.status === status
					? 'border-accent bg-accent-soft text-accent-ink'
					: 'border-line text-ink-muted hover:border-ink-faint hover:text-ink'}"
			>
				<span class="size-1.5 rounded-full {STATUS_DOT[status]}"></span>
				{STATUS_LABELS[status]}
			</a>
		{/each}
	</div>

	<!-- Era filter — only meaningful once eras exist -->
	{#if data.eras.length}
		<div class="mb-6 flex flex-wrap items-center gap-2">
			<a
				href={buildUrl({ era: null })}
				class="rounded-full border px-2.5 py-1 text-xs font-medium transition-colors
				{data.filters.era === null
					? 'border-accent bg-accent-soft text-accent-ink'
					: 'border-line text-ink-muted hover:border-ink-faint hover:text-ink'}"
			>
				All eras
			</a>
			{#each data.eras as era (era.slug)}
				<a
					href={buildUrl({ era: era.slug })}
					class="rounded-full border px-2.5 py-1 text-xs font-medium transition-colors
					{data.filters.era === era.slug
						? 'border-accent bg-accent-soft text-accent-ink'
						: 'border-line text-ink-muted hover:border-ink-faint hover:text-ink'}"
				>
					{era.name}
				</a>
			{/each}
		</div>
	{/if}

	{#if data.items.length}
		{#each bands as band (band.slug ?? '∅')}
			{#if !flat}
				<h2
					class="mt-7 mb-2 flex items-baseline gap-2 font-prose text-lg font-semibold text-ink first:mt-0
					{band.slug ? '' : 'text-ink-muted italic'}"
				>
					{band.name}
					<span class="text-xs font-normal text-ink-faint not-italic">
						{band.events.length}
						{band.events.length === 1 ? 'event' : 'events'}
					</span>
				</h2>
			{/if}

			<ol class="relative ml-1.5 border-l border-line-soft">
				{#each band.events as ev (ev.id)}
					{@const date = dateLabel(ev)}
					<li class="group relative pb-1">
						<span
							class="absolute top-3.5 -left-[5px] size-2.5 rounded-full border-2 border-paper {STATUS_DOT[
								ev.status
							]}"
						></span>
						<a
							href="/entities/{ev.slug}"
							class="block rounded-lg py-2.5 pl-5 pr-3 transition-colors hover:bg-surface"
						>
							{#if date}
								<span class="font-mono text-xs tracking-tight text-accent-ink/80">{date}</span>
							{:else}
								<span class="font-mono text-xs text-ink-faint italic">undated</span>
							{/if}
							<span class="mt-0.5 flex flex-wrap items-baseline gap-x-2.5 gap-y-0.5">
								<span
									class="font-prose text-[1.05rem] font-medium text-ink group-hover:text-accent-ink"
								>
									{ev.name}
								</span>
								<StatusBadge status={ev.status} size="xs" />
							</span>
							{#if ev.summary}
								<span class="mt-0.5 line-clamp-1 block text-sm text-ink-muted">{ev.summary}</span>
							{/if}
						</a>
					</li>
				{/each}
			</ol>
		{/each}
	{:else}
		<div class="py-16 text-center">
			<p class="font-prose text-lg text-ink-muted italic">The timeline is empty.</p>
			<p class="mt-1 text-sm text-ink-faint">
				Capture an <a href="/entities/new?type=event" class="text-accent-ink hover:underline">event</a>
				and give it an <code class="font-mono text-xs">order_index</code> to place it in time.
			</p>
		</div>
	{/if}
</div>
