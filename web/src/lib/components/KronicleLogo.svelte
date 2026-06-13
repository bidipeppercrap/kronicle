<script lang="ts">
	let { class: className = '' }: { class?: string } = $props();
</script>

<!-- Fortune-teller crystal ball: sphere on a stand with an inner glint.
     Drawn like a Lucide icon (currentColor stroke) so size-*/text-* classes work. -->
<svg
	xmlns="http://www.w3.org/2000/svg"
	width="24"
	height="24"
	viewBox="0 0 24 24"
	fill="none"
	stroke="currentColor"
	stroke-width="2"
	stroke-linecap="round"
	stroke-linejoin="round"
	class={className}
	aria-hidden="true"
>
	<!-- sphere -->
	<circle cx="12" cy="9.5" r="6" />
	<!-- stand -->
	<path d="M8 15 6.5 20h11L16 15" />
	<path d="M5.5 20h13" />
	<!-- inner sparkle / glint -->
	<path d="M10 7v3.5M8.25 8.75h3.5" />
</svg>
