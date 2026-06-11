<script lang="ts">
	import EntityRow from '$lib/components/EntityRow.svelte';
	import { timeAgo } from '$lib/format';
	import { HeartPulse, Hourglass, Link2Off, PenLine, Unplug } from '@lucide/svelte';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	const report = $derived(data.report);
	const clean = $derived(
		!report.broken_links.length && !report.orphans.length && !report.stale_stubs.length
	);
</script>

<svelte:head>
	<title>Vault health · Kronicle</title>
</svelte:head>

<div class="mx-auto w-full max-w-3xl px-4 py-8 sm:px-6 md:py-12">
	<h1 class="mb-1 font-prose text-2xl font-semibold tracking-tight text-ink">Vault health</h1>
	<p class="mb-8 text-sm text-ink-muted">
		Loose threads the vault can find for you — computed fresh on every visit, nothing stored.
	</p>

	{#if clean}
		<div class="rounded-xl border border-dashed border-line px-6 py-14 text-center">
			<HeartPulse class="mx-auto mb-3 size-6 text-status-canon" />
			<p class="font-prose text-lg text-ink-muted italic">All threads accounted for.</p>
			<p class="mt-1 text-sm text-ink-faint">
				No broken links, no orphaned entities, no stubs gathering dust.
			</p>
		</div>
	{/if}

	{#if report.broken_links.length}
		<section class="mb-10">
			<div class="mb-2 flex items-center gap-2 px-3">
				<Link2Off class="size-4 text-status-rejected" />
				<h2 class="font-prose text-lg font-semibold text-ink">Broken links</h2>
				<span class="text-xs text-ink-faint">
					[[wikilinks]] pointing at slugs that don't exist — typos, or ideas never captured
				</span>
			</div>
			<ul class="flex flex-col">
				{#each report.broken_links as item (item.id + item.missing_slug)}
					<li class="flex items-baseline gap-3 rounded-lg px-3 py-2.5 hover:bg-surface">
						<code class="shrink-0 font-mono text-sm text-status-rejected">
							[[{item.missing_slug}]]
						</code>
						{#if item.count > 1}
							<span class="shrink-0 text-xs text-ink-faint">×{item.count}</span>
						{/if}
						<span class="min-w-0 flex-1 truncate text-sm text-ink-muted">
							in <a href="/entities/{item.slug}" class="text-accent-ink hover:underline"
								>{item.name}</a
							>
						</span>
						<a
							href="/entities/{item.slug}/edit"
							class="flex shrink-0 items-center gap-1 text-xs text-ink-faint transition-colors hover:text-accent-ink"
						>
							<PenLine class="size-3" /> fix
						</a>
					</li>
				{/each}
			</ul>
		</section>
	{/if}

	{#if report.orphans.length}
		<section class="mb-10">
			<div class="mb-2 flex items-center gap-2 px-3">
				<Unplug class="size-4 text-status-stub" />
				<h2 class="font-prose text-lg font-semibold text-ink">Orphans</h2>
				<span class="text-xs text-ink-faint">
					no relationships, no mentions, no parent or children — disconnected from the vault
				</span>
			</div>
			<div class="flex flex-col">
				{#each report.orphans as entity (entity.id)}
					<EntityRow {entity} />
				{/each}
			</div>
		</section>
	{/if}

	{#if report.stale_stubs.length}
		<section class="mb-10">
			<div class="mb-2 flex items-center gap-2 px-3">
				<Hourglass class="size-4 text-status-stub" />
				<h2 class="font-prose text-lg font-semibold text-ink">Stubs gathering dust</h2>
				<span class="text-xs text-ink-faint">captured over two weeks ago, still waiting for triage</span>
			</div>
			<div class="flex flex-col">
				{#each report.stale_stubs as entity (entity.id)}
					<EntityRow {entity} />
				{/each}
			</div>
			<p class="mt-2 px-3 text-xs text-ink-faint">
				Oldest untouched {timeAgo(report.stale_stubs[0].updated_at)}. Promote them to drafts, or
				keep them as rejected — stubs are ideas waiting for a verdict.
			</p>
		</section>
	{/if}
</div>
