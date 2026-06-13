<script lang="ts">
	import { page } from '$app/state';
	import KronicleLogo from '$lib/components/KronicleLogo.svelte';
</script>

<div class="flex min-h-[60vh] flex-col items-center justify-center px-4 text-center">
	<KronicleLogo class="mb-4 size-8 text-ink-faint" />
	<h1 class="font-prose text-3xl font-semibold text-ink">
		{page.status === 404 ? 'This page was never written' : 'Something tore the page'}
	</h1>
	<p class="mt-2 max-w-md text-sm text-ink-muted">
		{page.error?.message ?? 'Unknown error'}
	</p>
	<div class="mt-6 flex gap-4 text-sm">
		<a href="/" class="text-accent-ink hover:underline">Back to the vault</a>
		{#if page.status === 404}
			<a href="/entities/new" class="text-accent-ink hover:underline">Write it into existence</a>
		{/if}
	</div>
</div>
