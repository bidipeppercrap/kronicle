<script lang="ts">
	import { enhance } from '$app/forms';
	import EntityRow from '$lib/components/EntityRow.svelte';
	import StatusBadge from '$lib/components/StatusBadge.svelte';
	import { toast } from '$lib/toast.svelte';
	import { ArrowRight, HeartPulse, Lightbulb, NotebookPen } from '@lucide/svelte';
	import type { ActionData, PageData } from './$types';

	let { data, form }: { data: PageData; form: ActionData } = $props();

	let nameInput = $state<HTMLInputElement | null>(null);
	let noteOpen = $state(false);
	let capturing = $state(false);

	const stats = $derived([
		{ label: 'entities', value: data.counts.total },
		{ label: 'canon', value: data.counts.canon },
		{ label: 'drafts', value: data.counts.draft },
		{ label: 'stubs', value: data.counts.stub }
	]);

	const healthNotes = $derived(
		[
			data.health.brokenLinks &&
				`${data.health.brokenLinks} broken ${data.health.brokenLinks === 1 ? 'link' : 'links'}`,
			data.health.orphans && `${data.health.orphans} ${data.health.orphans === 1 ? 'orphan' : 'orphans'}`,
			data.health.staleStubs &&
				`${data.health.staleStubs} stale ${data.health.staleStubs === 1 ? 'stub' : 'stubs'}`
		].filter((n): n is string => Boolean(n))
	);
</script>

<svelte:head>
	<title>Dashboard · Kronicle</title>
</svelte:head>

<div class="mx-auto w-full max-w-3xl px-4 py-8 sm:px-6 md:py-12">
	<!-- Quick capture: the core loop. One step, never a form with a type picker. -->
	<section class="animate-rise">
		<h1 class="mb-1 font-prose text-2xl font-semibold tracking-tight text-ink">
			What just struck you?
		</h1>
		<p class="mb-4 text-sm text-ink-muted">
			Name the idea and let it go — it lands as a <StatusBadge status="stub" size="xs" /> to triage
			later.
		</p>

		<form
			method="POST"
			action="?/capture"
			use:enhance={() => {
				capturing = true;
				return async ({ result, update }) => {
					capturing = false;
					if (result.type === 'success') {
						const captured = result.data?.captured as { name?: string } | undefined;
						toast(`Captured “${captured?.name ?? 'idea'}”`);
						noteOpen = false;
						await update();
						nameInput?.focus();
					} else {
						await update();
					}
				};
			}}
			class="overflow-hidden rounded-xl border border-line bg-surface shadow-sm transition-shadow focus-within:border-accent focus-within:shadow-md"
		>
			<div class="flex items-center gap-3 px-4">
				<Lightbulb class="size-5 shrink-0 text-status-stub" />
				<input
					bind:this={nameInput}
					name="name"
					required
					autocomplete="off"
					placeholder="A coven that worships the tide… a sword that remembers…"
					class="min-w-0 flex-1 bg-transparent py-4 font-prose text-lg text-ink outline-none placeholder:text-ink-faint"
				/>
				<button
					type="submit"
					disabled={capturing}
					class="my-2 flex shrink-0 items-center gap-1.5 rounded-lg bg-accent px-3.5 py-2 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
				>
					Capture
					<ArrowRight class="size-3.5" />
				</button>
			</div>
			{#if noteOpen}
				<textarea
					name="note"
					rows="2"
					placeholder="One or two sentences, just enough to find the thread again."
					class="block w-full resize-none border-t border-line-soft bg-transparent px-4 py-3 font-prose text-[0.95rem] text-ink outline-none placeholder:text-ink-faint"
				></textarea>
			{:else}
				<button
					type="button"
					onclick={() => (noteOpen = true)}
					class="flex w-full items-center gap-1.5 border-t border-line-soft px-4 py-2 text-xs text-ink-faint transition-colors hover:text-ink-muted"
				>
					<NotebookPen class="size-3.5" /> add a note
				</button>
			{/if}
		</form>
		{#if form?.error}
			<p class="mt-2 text-sm text-status-rejected">{form.error}</p>
		{/if}
	</section>

	<!-- Quick stats -->
	<section class="mt-10 grid grid-cols-2 gap-3 sm:grid-cols-4">
		{#each stats as stat (stat.label)}
			<div class="rounded-xl border border-line-soft bg-surface px-4 py-3">
				<div class="font-prose text-2xl font-semibold text-ink tabular-nums">{stat.value}</div>
				<div class="text-xs tracking-wider text-ink-faint uppercase">{stat.label}</div>
			</div>
		{/each}
	</section>

	{#if healthNotes.length}
		<a
			href="/health"
			class="mt-4 flex items-center gap-2 rounded-xl border border-status-stub/40 bg-accent-soft/60 px-4 py-2.5 text-sm text-ink-muted transition-colors hover:border-accent hover:text-ink"
		>
			<HeartPulse class="size-4 shrink-0 text-status-stub" />
			<span class="min-w-0 flex-1 truncate">{healthNotes.join(' · ')}</span>
			<ArrowRight class="size-3.5 shrink-0" />
		</a>
	{/if}

	<!-- Stubs awaiting triage -->
	{#if data.stubs.length}
		<section class="mt-10">
			<div class="mb-2 flex items-baseline justify-between px-3">
				<h2 class="font-prose text-lg font-semibold text-ink">Waiting for triage</h2>
				<a
					href="/entities?status=stub"
					class="text-xs text-ink-faint transition-colors hover:text-accent-ink"
				>
					all {data.counts.stub} stubs →
				</a>
			</div>
			<div class="flex flex-col">
				{#each data.stubs as entity (entity.id)}
					<EntityRow {entity} />
				{/each}
			</div>
		</section>
	{/if}

	<!-- Recently touched -->
	{#if data.recent.length}
		<section class="mt-10">
			<div class="mb-2 flex items-baseline justify-between px-3">
				<h2 class="font-prose text-lg font-semibold text-ink">Recently touched</h2>
				<a href="/entities" class="text-xs text-ink-faint transition-colors hover:text-accent-ink">
					all entities →
				</a>
			</div>
			<div class="flex flex-col">
				{#each data.recent as entity (entity.id)}
					<EntityRow {entity} />
				{/each}
			</div>
		</section>
	{:else}
		<section class="mt-14 text-center">
			<p class="font-prose text-lg text-ink-muted italic">The vault is empty — for now.</p>
			<p class="mt-1 text-sm text-ink-faint">Capture the first spark above.</p>
		</section>
	{/if}
</div>
