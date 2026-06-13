<script lang="ts">
	import { page } from '$app/state';
	import favicon from '$lib/assets/favicon.svg';
	import AiChatPanel from '$lib/components/AiChatPanel.svelte';
	import CommandPalette from '$lib/components/CommandPalette.svelte';
	import KronicleLogo from '$lib/components/KronicleLogo.svelte';
	import { isMac, modKey } from '$lib/platform';
	import { toasts } from '$lib/toast.svelte';
	import {
		CalendarClock,
		CirclePlus,
		Command as CommandIcon,
		Compass,
		HeartPulse,
		LayoutDashboard,
		Library,
		Moon,
		Search,
		Settings,
		Sparkles,
		Sun
	} from '@lucide/svelte';
	import '../app.css';

	let { children } = $props();

	let paletteOpen = $state(false);
	let chatOpen = $state(false);
	let dark = $state(false);

	$effect(() => {
		dark = document.documentElement.classList.contains('dark');
	});

	function toggleTheme() {
		dark = !dark;
		document.documentElement.classList.toggle('dark', dark);
		localStorage.setItem('kronicle-theme', dark ? 'dark' : 'light');
	}

	const nav = [
		{ label: 'Dashboard', href: '/', icon: LayoutDashboard },
		{ label: 'Entities', href: '/entities', icon: Library },
		{ label: 'Timeline', href: '/timeline', icon: CalendarClock },
		{ label: 'Search', href: '/search', icon: Search },
		{ label: 'Health', href: '/health', icon: HeartPulse },
		{ label: 'Settings', href: '/settings', icon: Settings }
	];

	function isActive(href: string): boolean {
		if (href === '/') return page.url.pathname === '/';
		return page.url.pathname.startsWith(href);
	}
</script>

<svelte:window
	onkeydown={(e) => {
		if ((e.metaKey || e.ctrlKey) && (e.key === 'j' || e.key === 'J')) {
			e.preventDefault();
			chatOpen = !chatOpen;
		}
	}}
/>

<svelte:head>
	<link rel="icon" href={favicon} />
	<title>Kronicle</title>
</svelte:head>

<div class="flex min-h-dvh">
	<!-- Sidebar (desktop) -->
	<aside
		class="sticky top-0 hidden h-dvh w-56 shrink-0 flex-col border-r border-line-soft bg-inset/50 px-3 py-5 md:flex"
	>
		<a href="/" class="mb-7 flex items-center gap-2.5 px-2">
			<KronicleLogo class="size-5 text-accent" />
			<span class="font-prose text-xl font-semibold tracking-tight text-ink">Kronicle</span>
		</a>

		<nav class="flex flex-col gap-0.5">
			{#each nav as item (item.href)}
				<a
					href={item.href}
					class="flex items-center gap-2.5 rounded-lg px-2.5 py-2 text-sm transition-colors
					{isActive(item.href)
						? 'bg-accent-soft font-medium text-accent-ink'
						: 'text-ink-muted hover:bg-surface hover:text-ink'}"
				>
					<item.icon class="size-4" />
					{item.label}
				</a>
			{/each}
		</nav>

		<a
			href="/entities/new"
			class="mt-5 flex items-center gap-2.5 rounded-lg border border-line bg-surface px-2.5 py-2 text-sm font-medium text-ink shadow-xs transition-colors hover:border-accent hover:text-accent-ink"
		>
			<CirclePlus class="size-4 text-accent" />
			New entity
		</a>

		<button
			type="button"
			onclick={() => (paletteOpen = true)}
			class="mt-2 flex items-center gap-2.5 rounded-lg px-2.5 py-2 text-sm text-ink-muted transition-colors hover:bg-surface hover:text-ink"
		>
			{#if isMac}
				<CommandIcon class="size-4" />
			{:else}
				<Compass class="size-4" />
			{/if}
			<span class="flex-1 text-left">Jump or capture</span>
			<kbd class="rounded border border-line bg-inset px-1.5 py-0.5 font-mono text-[0.625rem] text-ink-faint">
				{modKey}K
			</kbd>
		</button>

		<button
			type="button"
			onclick={() => (chatOpen = !chatOpen)}
			class="mt-1 flex items-center gap-2.5 rounded-lg px-2.5 py-2 text-sm transition-colors
			{chatOpen
				? 'bg-accent-soft font-medium text-accent-ink'
				: 'text-ink-muted hover:bg-surface hover:text-ink'}"
		>
			<Sparkles class="size-4" />
			<span class="flex-1 text-left">Chat</span>
			<kbd class="rounded border border-line bg-inset px-1.5 py-0.5 font-mono text-[0.625rem] text-ink-faint">
				{modKey}J
			</kbd>
		</button>

		<div class="mt-auto px-1">
			<button
				type="button"
				onclick={toggleTheme}
				class="flex w-full items-center gap-2.5 rounded-lg px-1.5 py-2 text-sm text-ink-muted transition-colors hover:bg-surface hover:text-ink"
				aria-label="Toggle theme"
			>
				{#if dark}
					<Sun class="size-4" /> Paper
				{:else}
					<Moon class="size-4" /> Candlelit
				{/if}
			</button>
		</div>
	</aside>

	<!-- Top bar (mobile) -->
	<div class="flex min-w-0 flex-1 flex-col">
		<header
			class="sticky top-0 z-40 flex items-center gap-1 border-b border-line-soft bg-paper/90 px-3 py-2.5 backdrop-blur md:hidden"
		>
			<a href="/" class="mr-auto flex items-center gap-2 px-1">
				<KronicleLogo class="size-4.5 text-accent" />
				<span class="font-prose text-lg font-semibold text-ink">Kronicle</span>
			</a>
			{#each nav as item (item.href)}
				<a
					href={item.href}
					class="rounded-lg p-2 {isActive(item.href)
						? 'bg-accent-soft text-accent-ink'
						: 'text-ink-muted'}"
					aria-label={item.label}
				>
					<item.icon class="size-4.5" />
				</a>
			{/each}
			<button
				type="button"
				onclick={() => (paletteOpen = true)}
				class="rounded-lg p-2 text-ink-muted"
				aria-label="Command palette"
			>
				<Search class="size-4.5" />
			</button>
			<button
				type="button"
				onclick={() => (chatOpen = !chatOpen)}
				class="rounded-lg p-2 {chatOpen ? 'bg-accent-soft text-accent-ink' : 'text-ink-muted'}"
				aria-label="Chat"
			>
				<Sparkles class="size-4.5" />
			</button>
			<button
				type="button"
				onclick={toggleTheme}
				class="rounded-lg p-2 text-ink-muted"
				aria-label="Toggle theme"
			>
				{#if dark}<Sun class="size-4.5" />{:else}<Moon class="size-4.5" />{/if}
			</button>
		</header>

		<main class="min-w-0 flex-1">
			{@render children()}
		</main>
	</div>
</div>

<CommandPalette bind:open={paletteOpen} />
<AiChatPanel bind:open={chatOpen} />

<!-- Toasts -->
<div class="pointer-events-none fixed right-4 bottom-4 z-50 flex flex-col gap-2">
	{#each toasts as t (t.id)}
		<div
			class="pointer-events-auto animate-rise rounded-lg border px-4 py-2.5 text-sm shadow-lg
			{t.kind === 'err'
				? 'border-status-rejected/40 bg-surface text-status-rejected'
				: 'border-line bg-surface text-ink'}"
		>
			{#if t.href}
				<a href={t.href} class="hover:text-accent-ink hover:underline">{t.text}</a>
			{:else}
				{t.text}
			{/if}
		</div>
	{/each}
</div>
