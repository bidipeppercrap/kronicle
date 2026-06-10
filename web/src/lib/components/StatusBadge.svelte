<script lang="ts">
	import { STATUS_BADGE } from '$lib/entityMeta';
	import { STATUS_LABELS, type Status } from '$lib/types';

	let { status, size = 'sm' }: { status: Status; size?: 'sm' | 'xs' } = $props();
</script>

<span
	class="inline-flex items-center rounded-full border font-medium tracking-wide uppercase
	{STATUS_BADGE[status]}
	{size === 'xs' ? 'px-1.5 py-px text-[0.625rem]' : 'px-2 py-0.5 text-[0.6875rem]'}"
>
	{STATUS_LABELS[status]}
</span>
