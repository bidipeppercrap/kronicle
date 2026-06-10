<script lang="ts">
	import EditorShell from './EditorShell.svelte';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();
</script>

<!-- Keyed so navigating between entities (e.g. after a slug rename) rebuilds
     the editing buffer instead of reusing stale state. -->
{#key data.entity.id + data.entity.slug}
	<EditorShell {data} />
{/key}
