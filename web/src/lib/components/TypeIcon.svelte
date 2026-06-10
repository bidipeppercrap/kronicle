<script lang="ts">
	import { TYPE_ICONS } from '$lib/entityMeta';
	import type { EntityType } from '$lib/types';

	let { type, class: cls = 'size-4' }: { type: EntityType; class?: string } = $props();

	const Icon = $derived(TYPE_ICONS[type]);
</script>

<Icon class={cls} aria-hidden="true" />
