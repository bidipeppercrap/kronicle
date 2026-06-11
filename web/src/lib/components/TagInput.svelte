<script lang="ts">
	import { X } from '@lucide/svelte';

	let { tags = $bindable() }: { tags: string[] } = $props();

	let draft = $state('');

	function addDraft() {
		const tag = draft.trim().replace(/,+$/, '').trim();
		draft = '';
		if (tag && !tags.includes(tag)) tags.push(tag);
	}

	function onkeydown(e: KeyboardEvent) {
		if (e.key === 'Enter' || e.key === ',') {
			e.preventDefault();
			addDraft();
		} else if (e.key === 'Backspace' && !draft && tags.length) {
			tags.pop();
		}
	}
</script>

<div
	class="flex flex-wrap items-center gap-1.5 rounded-lg border border-line bg-surface px-2 py-1.5 focus-within:border-accent"
>
	{#each tags as tag, i (tag)}
		<span
			class="flex items-center gap-1 rounded-full border border-line-soft bg-inset px-2 py-0.5 text-xs text-ink"
		>
			{tag}
			<button
				type="button"
				onclick={() => tags.splice(i, 1)}
				class="rounded text-ink-faint transition-colors hover:text-status-rejected"
				aria-label="Remove tag {tag}"
			>
				<X class="size-3" />
			</button>
		</span>
	{/each}
	<input
		bind:value={draft}
		{onkeydown}
		onblur={addDraft}
		placeholder={tags.length ? '' : 'villain, book-2…'}
		class="min-w-20 flex-1 bg-transparent py-0.5 text-xs text-ink outline-none placeholder:text-ink-faint"
	/>
</div>
