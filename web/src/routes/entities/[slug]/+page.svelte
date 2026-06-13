<script lang="ts">
	import { enhance } from '$app/forms';
	import EntityRow from '$lib/components/EntityRow.svelte';
	import StatusBadge from '$lib/components/StatusBadge.svelte';
	import TypeIcon from '$lib/components/TypeIcon.svelte';
	import { STATUS_DOT } from '$lib/entityMeta';
	import { fullDate, metaLabel, timeAgo, wordCount } from '$lib/format';
	import { toast } from '$lib/toast.svelte';
	import {
		RELATIONSHIP_INVERSE_LABELS,
		RELATIONSHIP_LABELS,
		STATUSES,
		STATUS_LABELS,
		TYPE_LABELS,
		type Relationship
	} from '$lib/types';
	import {
		ChevronRight,
		PanelRightClose,
		PanelRightOpen,
		PenLine
	} from '@lucide/svelte';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	let sidebarOpen = $state(true);

	const entity = $derived(data.entity);
	const metaEntries = $derived(
		Object.entries(entity.metadata).filter(
			([k, v]) => k !== 'tags' && v !== null && v !== '' && v !== undefined
		)
	);
	const tags = $derived(
		Array.isArray(entity.metadata.tags)
			? entity.metadata.tags.filter((t): t is string => typeof t === 'string')
			: []
	);

	function relParts(rel: Relationship) {
		const outgoing = rel.source_id === entity.id;
		const otherId = outgoing ? rel.target_id : rel.source_id;
		return {
			verb: outgoing ? RELATIONSHIP_LABELS[rel.type] : RELATIONSHIP_INVERSE_LABELS[rel.type],
			other: data.refs[otherId] ?? null,
			label: rel.label
		};
	}

	const words = $derived(wordCount(entity.content));
</script>

<svelte:head>
	<title>{entity.name} · Kronicle</title>
</svelte:head>

<div class="relative mx-auto flex w-full max-w-6xl gap-10 px-4 py-8 sm:px-8 md:py-12">
	<!-- The book page -->
	<article class="mx-auto min-w-0 max-w-[68ch] flex-1 animate-rise">
		<header class="mb-8">
			<div class="mb-3 flex flex-wrap items-center gap-2 text-sm text-ink-muted">
				<a
					href="/entities?type={entity.type}"
					class="flex items-center gap-1.5 transition-colors hover:text-accent-ink"
				>
					<TypeIcon type={entity.type} class="size-4" />
					{TYPE_LABELS[entity.type]}
				</a>
				{#if data.parent}
					<ChevronRight class="size-3.5 text-ink-faint" />
					<a href="/entities/{data.parent.slug}" class="transition-colors hover:text-accent-ink">
						{data.parent.name}
					</a>
				{/if}
				<span class="ml-auto flex items-center gap-2">
					<StatusBadge status={entity.status} />
					<a
						href="/entities/{entity.slug}/edit"
						class="flex items-center gap-1.5 rounded-lg border border-line bg-surface px-2.5 py-1 text-xs font-medium text-ink transition-colors hover:border-accent hover:text-accent-ink"
					>
						<PenLine class="size-3.5" /> Edit
					</a>
					<button
						type="button"
						class="hidden rounded-lg p-1.5 text-ink-faint transition-colors hover:bg-surface hover:text-ink lg:block"
						onclick={() => (sidebarOpen = !sidebarOpen)}
						aria-label={sidebarOpen ? 'Hide sidebar' : 'Show sidebar'}
					>
						{#if sidebarOpen}<PanelRightClose class="size-4" />{:else}<PanelRightOpen
								class="size-4"
							/>{/if}
					</button>
				</span>
			</div>

			<h1
				class="font-prose text-4xl font-semibold tracking-tight text-balance text-ink sm:text-[2.75rem]"
				style="line-height: 1.15"
			>
				{entity.name}
			</h1>
			{#if entity.summary}
				<p class="mt-3 font-prose text-lg text-ink-muted italic">{entity.summary}</p>
			{/if}
		</header>

		{#if data.html}
			<div class="prose-book">
				<!-- eslint-disable-next-line svelte/no-at-html-tags — own vault content -->
				{@html data.html}
			</div>
			<p class="mt-10 text-xs text-ink-faint">
				{words.toLocaleString()} words · updated {timeAgo(entity.updated_at)}
			</p>
		{:else}
			<div class="rounded-xl border border-dashed border-line px-6 py-10 text-center">
				<p class="font-prose text-ink-muted italic">This page is still blank.</p>
				<a
					href="/entities/{entity.slug}/edit"
					class="mt-2 inline-flex items-center gap-1.5 text-sm text-accent-ink hover:underline"
				>
					<PenLine class="size-3.5" /> Start writing
				</a>
			</div>
		{/if}

		{#if data.children.length}
			<section class="mt-12">
				<h2 class="mb-2 px-3 font-prose text-lg font-semibold text-ink">
					{entity.type === 'story' ? 'Chapters' : 'Within'}
				</h2>
				<div class="flex flex-col">
					{#each data.children as child (child.id)}
						<EntityRow entity={child} />
					{/each}
				</div>
			</section>
		{/if}
	</article>

	<!-- Recessed chrome: the margin notes -->
	{#if sidebarOpen}
		<aside class="hidden w-64 shrink-0 lg:block">
			<div class="sticky top-8 flex flex-col gap-7 text-sm">
				<!-- Status: the triage loop, one click away -->
				<section>
					<h3 class="mb-2 text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase">
						Status
					</h3>
					<form
						method="POST"
						action="?/setStatus"
						use:enhance={() =>
							async ({ result, update }) => {
								if (result.type === 'success') toast('Status updated');
								await update();
							}}
						class="grid grid-cols-2 gap-1.5"
					>
						{#each STATUSES as status (status)}
							<button
								name="status"
								value={status}
								disabled={entity.status === status}
								class="flex items-center gap-1.5 rounded-lg border px-2 py-1.5 text-xs transition-colors
								{entity.status === status
									? 'border-accent bg-accent-soft font-medium text-accent-ink'
									: 'border-line text-ink-muted hover:border-ink-faint hover:text-ink'}"
							>
								<span class="size-1.5 rounded-full {STATUS_DOT[status]}"></span>
								{STATUS_LABELS[status]}
							</button>
						{/each}
					</form>
				</section>

				{#if metaEntries.length}
					<section>
						<h3 class="mb-2 text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase">
							Details
						</h3>
						<dl class="flex flex-col gap-1.5">
							{#each metaEntries as [key, value] (key)}
								<div class="flex items-baseline justify-between gap-3">
									<dt class="text-ink-faint">{metaLabel(key)}</dt>
									<dd class="text-right text-ink">
										{#if key === 'era' && typeof value === 'string'}
											<a href="/entities/{value}" class="text-accent-ink hover:underline">
												{value.replaceAll('-', ' ')}
											</a>
										{:else}
											{String(value)}
										{/if}
									</dd>
								</div>
							{/each}
						</dl>
					</section>
				{/if}

				{#if tags.length}
					<section>
						<h3 class="mb-2 text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase">
							Tags
						</h3>
						<div class="flex flex-wrap gap-1.5">
							{#each tags as tag (tag)}
								<a
									href="/entities?tag={encodeURIComponent(tag)}"
									class="rounded-full border border-line bg-surface px-2.5 py-0.5 text-xs text-ink-muted transition-colors hover:border-accent hover:text-accent-ink"
								>
									{tag}
								</a>
							{/each}
						</div>
					</section>
				{/if}

				{#if entity.relationships.length}
					<section>
						<h3 class="mb-2 text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase">
							Relationships
						</h3>
						<ul class="flex flex-col gap-1.5">
							{#each entity.relationships as rel (rel.id)}
								{@const parts = relParts(rel)}
								<li class="leading-snug">
									<span class="text-ink-faint">{parts.verb}</span>
									{#if parts.other}
										<a
											href="/entities/{parts.other.slug}"
											class="text-accent-ink hover:underline"
										>
											{parts.other.name}
										</a>
									{:else}
										<span class="text-ink-muted">?</span>
									{/if}
									{#if parts.label}
										<span class="text-xs text-ink-faint">— {parts.label}</span>
									{/if}
								</li>
							{/each}
						</ul>
					</section>
				{/if}

				{#if data.backlinks.length}
					<section>
						<h3 class="mb-2 text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase">
							Mentioned in
						</h3>
						<ul class="flex flex-col gap-1.5">
							{#each data.backlinks as link (link.id)}
								<li class="flex items-center gap-2 leading-snug">
									<TypeIcon type={link.type} class="size-3.5 shrink-0 text-ink-faint" />
									<a href="/entities/{link.slug}" class="truncate text-accent-ink hover:underline">
										{link.name}
									</a>
								</li>
							{/each}
						</ul>
					</section>
				{/if}

				{#if entity.media.length}
					<section>
						<h3 class="mb-2 text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase">
							Media
						</h3>
						<div class="grid grid-cols-2 gap-2">
							{#each entity.media as item (item.id)}
								<img
									src="/api/media/{item.id}/file"
									alt={item.alt_text ?? item.media_type}
									loading="lazy"
									class="aspect-square rounded-lg border border-line-soft object-cover"
								/>
							{/each}
						</div>
					</section>
				{/if}

				<section class="border-t border-line-soft pt-4 text-xs text-ink-faint">
					<p class="font-mono">[[{entity.slug}]]</p>
					<p class="mt-1.5" title={fullDate(entity.created_at)}>
						created {timeAgo(entity.created_at)}
					</p>
					<p title={fullDate(entity.updated_at)}>updated {timeAgo(entity.updated_at)}</p>
				</section>
			</div>
		</aside>
	{/if}
</div>
