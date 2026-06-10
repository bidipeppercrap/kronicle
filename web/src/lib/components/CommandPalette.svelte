<script lang="ts">
	import { goto } from '$app/navigation';
	import StatusBadge from '$lib/components/StatusBadge.svelte';
	import TypeIcon from '$lib/components/TypeIcon.svelte';
	import { toast } from '$lib/toast.svelte';
	import type { Entity, ListResponse } from '$lib/types';
	import { TYPE_LABELS } from '$lib/types';
	import { CirclePlus, Compass, LayoutDashboard, Library, Search } from '@lucide/svelte';
	import { Command, Dialog } from 'bits-ui';

	let { open = $bindable(false) }: { open?: boolean } = $props();

	let query = $state('');
	let results = $state<Entity[]>([]);
	let recent = $state<Entity[]>([]);
	let capturing = $state(false);
	let timer: ReturnType<typeof setTimeout> | undefined;

	const pages = [
		{ label: 'Dashboard', href: '/', icon: LayoutDashboard },
		{ label: 'All entities', href: '/entities', icon: Library },
		{ label: 'Search', href: '/search', icon: Search },
		{ label: 'New entity', href: '/entities/new', icon: CirclePlus }
	];

	$effect(() => {
		if (!open) return;
		query = '';
		results = [];
		fetch('/api/entities?limit=8')
			.then((r) => r.json() as Promise<ListResponse<Entity>>)
			.then((d) => (recent = d.items))
			.catch(() => {});
	});

	function onQuery(q: string) {
		clearTimeout(timer);
		if (!q.trim()) {
			results = [];
			return;
		}
		timer = setTimeout(async () => {
			try {
				const res = await fetch(`/api/search?q=${encodeURIComponent(q.trim())}&limit=10`);
				const data = (await res.json()) as ListResponse<Entity>;
				results = data.items;
			} catch {
				results = [];
			}
		}, 150);
	}

	$effect(() => {
		onQuery(query);
	});

	function jump(slug: string) {
		open = false;
		goto(`/entities/${slug}`);
	}

	async function capture() {
		const name = query.trim();
		if (!name || capturing) return;
		capturing = true;
		try {
			const res = await fetch('/api/entities', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ name })
			});
			if (!res.ok) throw new Error();
			const entity = (await res.json()) as Entity;
			toast(`Captured “${entity.name}” as a stub`, 'ok', `/entities/${entity.slug}`);
			open = false;
		} catch {
			toast('Capture failed — is the API running?', 'err');
		} finally {
			capturing = false;
		}
	}

	const shown = $derived(query.trim() ? results : recent);
</script>

<svelte:window
	onkeydown={(e) => {
		if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
			e.preventDefault();
			open = !open;
		}
	}}
/>

<Dialog.Root bind:open>
	<Dialog.Portal>
		<Dialog.Overlay
			class="fixed inset-0 z-50 bg-[oklch(0.2_0.015_70/0.45)] backdrop-blur-[2px] dark:bg-[oklch(0.1_0.01_65/0.6)]"
		/>
		<Dialog.Content
			class="fixed top-[14vh] left-1/2 z-50 w-[min(38rem,calc(100vw-2rem))] -translate-x-1/2 animate-rise overflow-hidden rounded-xl border border-line bg-surface shadow-2xl shadow-[rgb(var(--shadow-tint)/0.25)]"
			aria-label="Command palette"
		>
			<Command.Root shouldFilter={false} class="flex flex-col">
				<Command.Input
					bind:value={query}
					placeholder="Jump to an entity, or type a new idea…"
					class="w-full border-b border-line-soft bg-transparent px-5 py-4 font-prose text-lg text-ink outline-none placeholder:text-ink-faint"
				/>
				<Command.List class="max-h-[50vh] overflow-y-auto p-2">
					<Command.Viewport>
						{#if query.trim()}
							<Command.Group>
								<Command.GroupHeading class="px-3 pt-2 pb-1 text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase">
									Capture
								</Command.GroupHeading>
								<Command.GroupItems>
									<Command.Item
										value="__capture"
										onSelect={capture}
										class="flex cursor-pointer items-center gap-3 rounded-lg px-3 py-2.5 text-sm text-ink data-selected:bg-accent-soft"
									>
										<CirclePlus class="size-4 text-status-stub" />
										<span>
											Capture <strong class="font-prose">“{query.trim()}”</strong> as a new stub
										</span>
									</Command.Item>
								</Command.GroupItems>
							</Command.Group>
						{/if}

						{#if shown.length}
							<Command.Group>
								<Command.GroupHeading class="px-3 pt-2 pb-1 text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase">
									{query.trim() ? 'Entities' : 'Recently touched'}
								</Command.GroupHeading>
								<Command.GroupItems>
									{#each shown as entity (entity.id)}
										<Command.Item
											value={entity.id}
											onSelect={() => jump(entity.slug)}
											class="flex cursor-pointer items-center gap-3 rounded-lg px-3 py-2.5 data-selected:bg-accent-soft"
										>
											<span class="text-ink-faint"><TypeIcon type={entity.type} /></span>
											<span class="min-w-0 flex-1 truncate font-prose text-[0.95rem] text-ink">
												{entity.name}
											</span>
											<span class="text-xs text-ink-faint">{TYPE_LABELS[entity.type]}</span>
											<StatusBadge status={entity.status} size="xs" />
										</Command.Item>
									{/each}
								</Command.GroupItems>
							</Command.Group>
						{/if}

						{#if !query.trim()}
							<Command.Group>
								<Command.GroupHeading class="px-3 pt-2 pb-1 text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase">
									Go to
								</Command.GroupHeading>
								<Command.GroupItems>
									{#each pages as page (page.href)}
										<Command.Item
											value={page.href}
											onSelect={() => {
												open = false;
												goto(page.href);
											}}
											class="flex cursor-pointer items-center gap-3 rounded-lg px-3 py-2.5 text-sm text-ink data-selected:bg-accent-soft"
										>
											<page.icon class="size-4 text-ink-faint" />
											{page.label}
										</Command.Item>
									{/each}
								</Command.GroupItems>
							</Command.Group>
						{:else if !shown.length}
							<div class="flex items-center gap-3 px-3 py-6 text-sm text-ink-faint">
								<Compass class="size-4" />
								No entities match — capture it as a stub instead?
							</div>
						{/if}
					</Command.Viewport>
				</Command.List>
			</Command.Root>
		</Dialog.Content>
	</Dialog.Portal>
</Dialog.Root>
