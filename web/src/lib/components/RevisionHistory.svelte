<script lang="ts">
	import { timeAgo, wordCount } from '$lib/format';
	import { renderMarkdown } from '$lib/markdown';
	import { toast } from '$lib/toast.svelte';
	import type { Entity, Revision } from '$lib/types';
	import { History, LoaderCircle } from '@lucide/svelte';
	import { Dialog } from 'bits-ui';

	let {
		entityId,
		onrestored
	}: {
		entityId: string;
		/** Called with the updated entity after a successful restore. */
		onrestored: (updated: Entity) => void;
	} = $props();

	let items = $state<Revision[] | null>(null);
	let loading = $state(false);
	let selected = $state<Revision | null>(null);
	let restoring = $state(false);

	async function load() {
		loading = true;
		try {
			const res = await fetch(`/api/entities/${entityId}/revisions`);
			if (!res.ok) throw new Error(`Failed to load revisions (${res.status})`);
			items = ((await res.json()) as { items: Revision[] }).items;
		} catch (e) {
			toast(e instanceof Error ? e.message : 'Failed to load revisions', 'err');
		} finally {
			loading = false;
		}
	}

	async function restore() {
		if (!selected) return;
		restoring = true;
		try {
			const res = await fetch(`/api/entities/${entityId}/revisions/${selected.id}/restore`, {
				method: 'POST'
			});
			if (!res.ok) {
				const body = (await res.json().catch(() => null)) as { error?: string } | null;
				throw new Error(body?.error ?? `Restore failed (${res.status})`);
			}
			const updated = (await res.json()) as Entity;
			selected = null;
			onrestored(updated);
			toast('Revision restored — the replaced text was snapshotted too');
			await load();
		} catch (e) {
			toast(e instanceof Error ? e.message : 'Restore failed', 'err');
		} finally {
			restoring = false;
		}
	}
</script>

<section>
	<h3 class="mb-1.5 text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase">
		History
	</h3>
	{#if items === null}
		<button
			type="button"
			onclick={load}
			disabled={loading}
			class="flex items-center gap-1.5 rounded-lg border border-line bg-surface px-2.5 py-1.5 text-xs text-ink-muted transition-colors hover:border-accent hover:text-accent-ink disabled:opacity-50"
		>
			{#if loading}
				<LoaderCircle class="size-3.5 animate-spin" />
			{:else}
				<History class="size-3.5" />
			{/if}
			Show revisions
		</button>
	{:else if items.length === 0}
		<p class="text-xs leading-snug text-ink-faint">
			No snapshots yet — one is taken when saved prose changes.
		</p>
	{:else}
		<ul class="flex flex-col gap-0.5">
			{#each items as rev (rev.id)}
				<li>
					<button
						type="button"
						onclick={() => (selected = rev)}
						class="flex w-full items-baseline justify-between gap-2 rounded-lg px-2 py-1 text-left text-xs text-ink-muted transition-colors hover:bg-surface hover:text-ink"
					>
						<span>{timeAgo(rev.created_at)}</span>
						<span class="shrink-0 text-ink-faint">{wordCount(rev.content).toLocaleString()} words</span>
					</button>
				</li>
			{/each}
		</ul>
	{/if}
</section>

<Dialog.Root open={selected !== null} onOpenChange={(open) => !open && (selected = null)}>
	<Dialog.Portal>
		<Dialog.Overlay class="fixed inset-0 z-50 bg-[oklch(0.2_0.015_70/0.45)] backdrop-blur-[2px]" />
		<Dialog.Content
			class="fixed top-1/2 left-1/2 z-50 flex max-h-[min(40rem,calc(100dvh-4rem))] w-[min(44rem,calc(100vw-2rem))] -translate-x-1/2 -translate-y-1/2 animate-rise flex-col rounded-xl border border-line bg-surface shadow-2xl"
		>
			{#if selected}
				<div class="border-b border-line-soft px-6 py-4">
					<Dialog.Title class="font-prose text-lg font-semibold text-ink">
						Snapshot from {timeAgo(selected.created_at)}
					</Dialog.Title>
					<Dialog.Description class="mt-0.5 text-xs text-ink-faint">
						{wordCount(selected.content).toLocaleString()} words — restoring snapshots the current
						text first, so nothing is lost.
					</Dialog.Description>
				</div>
				<div class="min-h-0 flex-1 overflow-y-auto px-6 py-5">
					{#if selected.content.trim()}
						<div class="prose-book">
							{@html renderMarkdown(selected.content)}
						</div>
					{:else}
						<p class="text-sm text-ink-faint">This snapshot is empty.</p>
					{/if}
				</div>
				<div class="flex justify-end gap-2 border-t border-line-soft px-6 py-4">
					<Dialog.Close
						class="rounded-lg border border-line px-3 py-1.5 text-sm text-ink transition-colors hover:bg-inset"
					>
						Cancel
					</Dialog.Close>
					<button
						type="button"
						onclick={restore}
						disabled={restoring}
						class="flex items-center gap-1.5 rounded-lg bg-accent px-3 py-1.5 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
					>
						{#if restoring}
							<LoaderCircle class="size-3.5 animate-spin" />
						{/if}
						Restore this version
					</button>
				</div>
			{/if}
		</Dialog.Content>
	</Dialog.Portal>
</Dialog.Root>
