<script lang="ts">
	import StatusBadge from '$lib/components/StatusBadge.svelte';
	import TypeIcon from '$lib/components/TypeIcon.svelte';
	import { timeAgo } from '$lib/format';
	import { TYPE_LABELS, type Entity } from '$lib/types';

	let {
		entity,
		showType = true
	}: {
		entity: Pick<Entity, 'slug' | 'type' | 'name' | 'status' | 'summary' | 'updated_at'>;
		showType?: boolean;
	} = $props();
</script>

<a
	href="/entities/{entity.slug}"
	class="group flex items-baseline gap-3 rounded-lg px-3 py-2.5 transition-colors hover:bg-surface"
>
	<span class="self-center text-ink-faint transition-colors group-hover:text-accent">
		<TypeIcon type={entity.type} class="size-[1.05rem]" />
	</span>
	<span class="min-w-0 flex-1">
		<span class="flex flex-wrap items-baseline gap-x-2.5 gap-y-0.5">
			<span class="font-prose text-[1.05rem] font-medium text-ink group-hover:text-accent-ink">
				{entity.name}
			</span>
			{#if showType}
				<span class="text-xs text-ink-faint">{TYPE_LABELS[entity.type]}</span>
			{/if}
		</span>
		{#if entity.summary}
			<span class="mt-0.5 line-clamp-1 block text-sm text-ink-muted">{entity.summary}</span>
		{/if}
	</span>
	<span class="hidden shrink-0 self-center text-xs whitespace-nowrap text-ink-faint sm:block">
		{timeAgo(entity.updated_at)}
	</span>
	<span class="shrink-0 self-center"><StatusBadge status={entity.status} size="xs" /></span>
</a>
