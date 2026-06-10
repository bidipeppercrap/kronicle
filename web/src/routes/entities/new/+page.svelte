<script lang="ts">
	import { enhance } from '$app/forms';
	import { page } from '$app/state';
	import EntityPicker, { type PickedEntity } from '$lib/components/EntityPicker.svelte';
	import TypeIcon from '$lib/components/TypeIcon.svelte';
	import { STATUS_DOT } from '$lib/entityMeta';
	import {
		ENTITY_TYPES,
		STATUSES,
		STATUS_LABELS,
		TYPE_LABELS,
		type EntityType,
		type Status
	} from '$lib/types';
	import type { ActionData } from './$types';

	let { form }: { form: ActionData } = $props();

	const initialType = page.url.searchParams.get('type');
	let type = $state<EntityType>(
		ENTITY_TYPES.includes(initialType as EntityType) ? (initialType as EntityType) : 'character'
	);
	let status = $state<Status>('draft');
	let parentSel = $state<PickedEntity | null>(null);
	let submitting = $state(false);
</script>

<svelte:head>
	<title>New entity · Kronicle</title>
</svelte:head>

<div class="mx-auto w-full max-w-xl px-4 py-8 sm:px-6 md:py-12">
	<h1 class="mb-1 font-prose text-2xl font-semibold tracking-tight text-ink">New entity</h1>
	<p class="mb-6 text-sm text-ink-muted">
		The full form — for when you already know what it is. The slug is generated for you; prose
		comes next, in the editor.
	</p>

	<form
		method="POST"
		use:enhance={() => {
			submitting = true;
			return async ({ update }) => {
				submitting = false;
				await update();
			};
		}}
		class="flex flex-col gap-5"
	>
		<div>
			<label
				for="new-name"
				class="mb-1.5 block text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase"
			>
				Name
			</label>
			<!-- svelte-ignore a11y_autofocus -->
			<input
				id="new-name"
				name="name"
				required
				autofocus
				autocomplete="off"
				placeholder="Guli · Bangsur Town · The Tide Coven…"
				class="w-full rounded-xl border border-line bg-surface px-4 py-3 font-prose text-lg text-ink shadow-sm outline-none placeholder:text-ink-faint focus:border-accent"
			/>
		</div>

		<fieldset>
			<legend class="mb-1.5 text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase">
				Type
			</legend>
			<div class="grid grid-cols-2 gap-1.5 sm:grid-cols-4">
				{#each ENTITY_TYPES as t (t)}
					<label
						class="flex cursor-pointer items-center gap-2 rounded-lg border px-2.5 py-2 text-sm transition-colors
						{type === t
							? 'border-accent bg-accent-soft font-medium text-accent-ink'
							: 'border-line text-ink-muted hover:border-ink-faint hover:text-ink'}"
					>
						<input type="radio" name="type" value={t} bind:group={type} class="sr-only" />
						<TypeIcon type={t} class="size-4" />
						{TYPE_LABELS[t]}
					</label>
				{/each}
			</div>
		</fieldset>

		<fieldset>
			<legend class="mb-1.5 text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase">
				Status
			</legend>
			<div class="flex flex-wrap gap-1.5">
				{#each STATUSES as s (s)}
					<label
						class="flex cursor-pointer items-center gap-1.5 rounded-full border px-3 py-1.5 text-xs font-medium transition-colors
						{status === s
							? 'border-accent bg-accent-soft text-accent-ink'
							: 'border-line text-ink-muted hover:border-ink-faint hover:text-ink'}"
					>
						<input type="radio" name="status" value={s} bind:group={status} class="sr-only" />
						<span class="size-1.5 rounded-full {STATUS_DOT[s]}"></span>
						{STATUS_LABELS[s]}
					</label>
				{/each}
			</div>
		</fieldset>

		<div>
			<label
				for="new-summary"
				class="mb-1.5 block text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase"
			>
				Summary <span class="font-normal normal-case">(optional)</span>
			</label>
			<textarea
				id="new-summary"
				name="summary"
				rows="2"
				placeholder="One or two sentences for cards and lists."
				class="w-full resize-y rounded-xl border border-line bg-surface px-4 py-3 font-prose text-sm text-ink shadow-sm outline-none placeholder:text-ink-faint focus:border-accent"
			></textarea>
		</div>

		<div>
			<span class="mb-1.5 block text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase">
				Parent <span class="font-normal normal-case">(chapter → story, building → city…)</span>
			</span>
			<EntityPicker bind:selected={parentSel} placeholder="None" />
			<input type="hidden" name="parent_id" value={parentSel?.id ?? ''} />
		</div>

		{#if form?.error}
			<p class="text-sm text-status-rejected">{form.error}</p>
		{/if}

		<div class="flex items-center gap-3">
			<button
				type="submit"
				disabled={submitting}
				class="rounded-xl bg-accent px-5 py-2.5 text-sm font-medium text-paper shadow-sm transition-opacity hover:opacity-90 disabled:opacity-50"
			>
				Create &amp; open editor
			</button>
			<a href="/entities" class="text-sm text-ink-muted transition-colors hover:text-ink">Cancel</a>
		</div>
	</form>
</div>
