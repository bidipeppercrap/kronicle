<script lang="ts">
	import { page } from '$app/state';
	import { invalidateAll } from '$app/navigation';
	import { unifiedDiff } from '$lib/diff';
	import { editorBridge } from '$lib/editorBridge.svelte';
	import { renderMarkdown } from '$lib/markdown';
	import { toast } from '$lib/toast.svelte';
	import {
		Check,
		CircleAlert,
		Eraser,
		LoaderCircle,
		ScanSearch,
		SendHorizontal,
		Sparkles,
		X
	} from '@lucide/svelte';

	/**
	 * Route-aware AI chat (DESIGN.md, AI Chat). One panel lives in the shell and
	 * its context follows the current route — the entity you're viewing, the
	 * timeline era you're on, or the whole vault. Stateless on the server: this
	 * component holds the whole conversation and sends it every turn. Write tools
	 * arrive as proposals; nothing changes until Apply, which goes through the
	 * normal REST save path (or merges into the open editor buffer).
	 */

	interface Proposal {
		id: string;
		tool: string;
		summary: string;
		args: Record<string, unknown>;
		status: 'pending' | 'applying' | 'applied' | 'discarded' | 'failed';
	}

	interface Turn {
		role: 'user' | 'assistant';
		text: string;
		/** [Context: …] marker emitted with this user turn — wire-only, not shown. */
		context?: string;
		proposals: Proposal[];
		reading: string[];
	}

	interface RouteContext {
		entity_id?: string;
		/** Short chip label shown in the header. */
		label: string;
		/** What the [Context: …] marker says when this becomes the live focus. */
		marker: string;
	}

	/** The slice of an entity's load data the chat reads off the current route. */
	interface EntityLike {
		id: string;
		name: string;
		type: string;
		status: string;
		content: string;
		summary: string;
	}

	let { open = $bindable(false) }: { open?: boolean } = $props();

	const TOOL_LABELS: Record<string, string> = {
		update_entity: 'Edit',
		create_entity: 'New entity',
		add_relationship: 'Add relationship',
		remove_relationship: 'Remove relationship'
	};

	const ROUTE_LABEL: Record<string, string> = {
		'/': 'the dashboard',
		'/entities': 'the entity list',
		'/search': 'search',
		'/graph': 'the relationship graph',
		'/health': 'vault health',
		'/settings': 'settings'
	};

	const VAULT: RouteContext = { label: 'whole vault', marker: 'now browsing the whole vault' };

	// ——— Route-derived context ———

	function routeEntity(): EntityLike | undefined {
		return (page.data as { entity?: EntityLike } | undefined)?.entity;
	}

	const routeContext = $derived.by((): RouteContext => {
		const ent = routeEntity();
		if (ent?.id) {
			return {
				entity_id: ent.id,
				label: ent.name,
				marker: `now viewing ${ent.name} (${ent.type}, ${ent.status})`
			};
		}
		const path = page.url.pathname;
		if (path.startsWith('/timeline')) {
			const era = page.url.searchParams.get('era');
			return {
				label: era ? `timeline · ${era}` : 'timeline',
				marker: era ? `now viewing the timeline (era ${era})` : 'now viewing the timeline'
			};
		}
		return { label: 'whole vault', marker: `now browsing ${ROUTE_LABEL[path] ?? 'the vault'}` };
	});

	// "Clear to vault-wide": talk to the whole vault from an entity page. Resets
	// on navigation so the chat re-attaches to wherever you land next.
	let detached = $state(false);
	let lastPath = page.url.pathname;
	$effect(() => {
		if (page.url.pathname !== lastPath) {
			lastPath = page.url.pathname;
			detached = false;
		}
	});

	const effective = $derived(detached ? VAULT : routeContext);

	let turns = $state<Turn[]>([]);
	let input = $state('');
	let inputEl = $state<HTMLTextAreaElement | null>(null);
	let busy = $state(false);
	let scrollEl = $state<HTMLElement | null>(null);
	/** Last context marker we sent — a new one is emitted only when it changes. */
	let lastSentMarker = $state<string | null>(null);
	/** Saved content for off-route update proposals, fetched lazily for the diff. */
	let baselines = $state<Record<string, string>>({});

	// Follow the stream: keep the transcript pinned to the bottom.
	$effect(() => {
		void turns.length;
		void turns.at(-1)?.text;
		void turns.at(-1)?.proposals.length;
		if (scrollEl) scrollEl.scrollTop = scrollEl.scrollHeight;
	});

	// Opening the panel (⌘/Ctrl-J or the sidebar toggle) drops the cursor
	// straight into the composer. The textarea only exists while open, so
	// inputEl flips null→element on mount and re-runs this once it's bound.
	$effect(() => {
		if (open) inputEl?.focus();
	});

	/**
	 * Strip the app-record markers ([Proposed …], [Context: …]) from assistant
	 * text. The client injects these into wire history as bookkeeping; the model
	 * is told never to type them, but sometimes it parrots a "[Proposed … —
	 * applied]" line as prose instead of calling a write tool — faking a proposal
	 * with no Apply button (and a "change" that never happened). Scrubbing them
	 * from both the rendered bubble and the history sent back keeps the fake off
	 * screen and stops it reinforcing itself next turn. Real proposals arrive as
	 * cards, so nothing real is lost. Only ever applied to assistant text — the
	 * [Context: …] prefix on user turns is a deliberate, separate marker.
	 */
	function visibleText(raw: string): string {
		return raw
			.replace(/\[(?:Proposed|Context)\b[^\]]*\]/g, '')
			// A marker still mid-stream (closing bracket not in yet) — drop the tail.
			.replace(/\[(?:Proposed|Context)\b[^\]]*$/g, '')
			.replace(/\n{3,}/g, '\n\n')
			.trim();
	}

	/**
	 * Wire-format history: plain {role, content}. Proposals and their outcomes,
	 * and the [Context: …] markers, are flattened into the turns so the model
	 * knows next turn what landed and where the writer is looking — the server
	 * remembers nothing (DESIGN.md).
	 */
	function wireHistory(): { role: string; content: string }[] {
		const msgs: { role: string; content: string }[] = [];
		for (const t of turns) {
			if (t.role === 'user') {
				const content = t.context ? `[Context: ${t.context}]\n\n${t.text}` : t.text;
				msgs.push({ role: 'user', content });
				continue;
			}
			let content = visibleText(t.text);
			for (const p of t.proposals) {
				const outcome =
					p.status === 'applied' ? 'applied' : p.status === 'discarded' ? 'discarded' : 'pending';
				content += `\n\n[Proposed ${p.id}: ${p.summary} — ${outcome}]`;
			}
			if (content.trim()) msgs.push({ role: 'assistant', content: content.trim() });
		}
		return msgs;
	}

	/** Best-known baseline to diff an update_entity proposal against. */
	function diffBase(id: string): string {
		if (editorBridge.entityId === id && editorBridge.current) return editorBridge.current.content;
		const ent = routeEntity();
		if (ent?.id === id) return ent.content;
		return baselines[id] ?? '';
	}

	/** Fetch saved content for a proposal whose entity isn't on-route or open. */
	async function ensureBaseline(id: string) {
		if (editorBridge.entityId === id) return;
		if (routeEntity()?.id === id) return;
		if (baselines[id] !== undefined) return;
		baselines[id] = '';
		try {
			const res = await fetch(`/api/entities/${id}`);
			if (res.ok) {
				const data = (await res.json()) as { content?: string };
				baselines[id] = data.content ?? '';
			}
		} catch {
			// Leave the empty baseline — the diff just renders as all-new.
		}
	}

	function handleEvent(turn: Turn, event: string, data: Record<string, unknown>) {
		if (event === 'text') {
			turn.text += String(data.delta ?? '');
		} else if (event === 'reading') {
			const detail = String(data.detail ?? '') || String(data.tool ?? 'the vault');
			turn.reading.push(`checking ${detail}…`);
		} else if (event === 'proposal') {
			if (data.tool === 'apply_proposal') {
				// Consent came from the writer's own message — apply the
				// referenced pending proposal right away (DESIGN.md). Only
				// proposals from *earlier* turns qualify: one created in this
				// same streaming turn was never seen, so it stays pending.
				const refId = (data.args as { id?: string })?.id;
				const ref = turns
					.filter((t) => t !== turn)
					.flatMap((t) => t.proposals)
					.find((p) => p.id === refId && (p.status === 'pending' || p.status === 'failed'));
				if (ref) void apply(ref);
				else if (turn.proposals.some((p) => p.id === refId)) {
					toast('The AI tried to apply its own new proposal — review it below', 'err');
				} else toast(`No pending proposal ${refId ?? ''} to apply`, 'err');
			} else {
				const proposal = { ...(data as unknown as Proposal), status: 'pending' as const };
				turn.proposals.push(proposal);
				if (proposal.tool === 'update_entity' && typeof proposal.args.id === 'string') {
					void ensureBaseline(proposal.args.id);
				}
			}
		} else if (event === 'error') {
			toast(String(data.message ?? 'AI chat failed'), 'err');
		}
	}

	/**
	 * Wipe the conversation back to a blank slate. The panel persists across
	 * open/close (it stays mounted in the shell), so this is the one-tap way to
	 * start over — transcript, the context markers, fetched baselines, and any
	 * manual whole-vault detach all reset. Nothing is ever written server-side.
	 */
	function clearChat() {
		turns = [];
		lastSentMarker = null;
		baselines = {};
		detached = false;
		input = '';
		inputEl?.focus();
	}

	async function send(e?: Event) {
		e?.preventDefault();
		const text = input.trim();
		if (!text || busy) return;
		input = '';
		// Tag the turn with a context marker whenever the focus differs from the
		// last one we sent (including the first message), so the transcript stays
		// self-describing once the writer navigates mid-conversation. Wire-only —
		// never shown in the bubble.
		const marker = effective.marker;
		const context = marker !== lastSentMarker ? marker : undefined;
		lastSentMarker = marker;
		const entityId = effective.entity_id;
		turns.push({ role: 'user', text, context, proposals: [], reading: [] });
		const history = wireHistory();
		// Read the turn back out of the $state array: mutations must go
		// through the reactive proxy, or the transcript never re-renders.
		turns.push({ role: 'assistant', text: '', proposals: [], reading: [] });
		const turn = turns[turns.length - 1];
		busy = true;
		try {
			const res = await fetch('/api/ai/chat', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ entity_id: entityId, messages: history })
			});
			if (!res.ok || !res.body) {
				const body = (await res.json().catch(() => null)) as { error?: string } | null;
				throw new Error(body?.error ?? `Chat failed (${res.status})`);
			}
			const reader = res.body.getReader();
			const decoder = new TextDecoder();
			let buf = '';
			for (;;) {
				const { done, value } = await reader.read();
				if (done) break;
				buf += decoder.decode(value, { stream: true });
				let i;
				while ((i = buf.indexOf('\n\n')) >= 0) {
					const block = buf.slice(0, i);
					buf = buf.slice(i + 2);
					let event = 'message';
					let data = '';
					for (const line of block.split('\n')) {
						if (line.startsWith('event:')) event = line.slice(6).trim();
						else if (line.startsWith('data:')) data += line.slice(5).trim();
					}
					if (data) handleEvent(turn, event, JSON.parse(data));
				}
			}
		} catch (err) {
			toast(err instanceof Error ? err.message : 'Chat failed', 'err');
			if (!turn.text && !turn.proposals.length) turns.splice(turns.indexOf(turn), 1);
		} finally {
			busy = false;
		}
	}

	async function rest(method: 'POST' | 'PUT' | 'DELETE', path: string, body?: unknown) {
		const res = await fetch(path, {
			method,
			headers: body !== undefined ? { 'Content-Type': 'application/json' } : undefined,
			body: body !== undefined ? JSON.stringify(body) : undefined
		});
		if (!res.ok) {
			const data = (await res.json().catch(() => null)) as { error?: string } | null;
			throw new Error(data?.error ?? `${method} failed (${res.status})`);
		}
	}

	/**
	 * Apply = dumb dispatch through the normal REST save path, then refetch
	 * (DESIGN.md). The one exception: an update to the entity open in the editor
	 * merges into the live buffer instead, so a PUT can't clobber unsaved prose.
	 */
	async function apply(p: Proposal) {
		if (p.status === 'applying' || p.status === 'applied') return;
		p.status = 'applying';
		try {
			if (p.tool === 'update_entity') {
				const { id, ...fields } = p.args as { id: string } & Record<string, unknown>;
				if (editorBridge.entityId === id && editorBridge.applyUpdate) {
					editorBridge.applyUpdate(fields);
				} else {
					await rest('PUT', `/api/entities/${id}`, fields);
					await invalidateAll();
				}
			} else if (p.tool === 'create_entity') {
				await rest('POST', '/api/entities', p.args);
				await invalidateAll();
			} else if (p.tool === 'add_relationship') {
				await rest('POST', '/api/relationships', p.args);
				await invalidateAll();
			} else if (p.tool === 'remove_relationship') {
				await rest('DELETE', `/api/relationships/${p.args.id}`);
				await invalidateAll();
			} else {
				throw new Error(`Unknown proposal tool: ${p.tool}`);
			}
			p.status = 'applied';
			toast(`Applied — ${p.summary}`);
		} catch (err) {
			p.status = 'failed';
			toast(err instanceof Error ? err.message : 'Apply failed', 'err');
		}
	}

	/** Compact arg rows for change cards — content gets the diff, not a row. */
	function argRows(p: Proposal): [string, string][] {
		return Object.entries(p.args)
			.filter(([k]) => k !== 'id' && k !== 'content')
			.map(([k, v]) => [
				k,
				typeof v === 'string' ? v : v === null ? '—' : JSON.stringify(v)
			]);
	}
</script>

{#if open}
	<aside
		class="fixed inset-y-0 right-0 z-40 flex w-full max-w-md animate-rise flex-col border-l border-line bg-paper shadow-2xl"
		aria-label="AI chat"
	>
		<header class="flex items-center gap-2.5 border-b border-line-soft px-4 py-3">
			<Sparkles class="size-4 shrink-0 text-accent-ink" />
			<div class="min-w-0 flex-1">
				<p class="text-sm font-medium text-ink">Chat</p>
				<p class="flex items-center gap-1.5 text-[0.6875rem] text-ink-faint">
					<span
						class="min-w-0 truncate rounded-full border border-line bg-surface px-1.5 py-px font-medium text-ink-muted"
					>
						{effective.label}
					</span>
					{#if routeContext.entity_id}
						<button
							type="button"
							onclick={() => (detached = !detached)}
							class="shrink-0 text-accent-ink transition-colors hover:underline"
						>
							{detached ? 'focus this page' : 'whole vault'}
						</button>
					{/if}
				</p>
			</div>
			{#if turns.length}
				<button
					type="button"
					onclick={clearChat}
					disabled={busy}
					class="rounded-lg p-1.5 text-ink-faint transition-colors hover:bg-surface hover:text-ink disabled:opacity-40"
					aria-label="Clear chat"
					title="Clear chat"
				>
					<Eraser class="size-4" />
				</button>
			{/if}
			<button
				type="button"
				onclick={() => (open = false)}
				class="rounded-lg p-1.5 text-ink-faint transition-colors hover:bg-surface hover:text-ink"
				aria-label="Close chat"
			>
				<X class="size-4" />
			</button>
		</header>

		<div bind:this={scrollEl} class="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto px-4 py-4">
			{#if !turns.length}
				<p class="m-auto max-w-[28ch] text-center text-sm text-ink-faint italic">
					Chatting about {effective.label}. Ask for a rewrite and you'll get a diff to apply or
					discard — clear it any time to start over.
				</p>
			{/if}

			{#each turns as turn, i (i)}
				{@const body = visibleText(turn.text)}
				{#if turn.role === 'user'}
					<div
						class="max-w-[85%] self-end rounded-xl bg-accent-soft px-3 py-2 text-sm whitespace-pre-wrap text-ink"
					>
						{turn.text}
					</div>
				{:else}
					<div class="flex flex-col gap-2">
						{#each turn.reading as note, k (k)}
							<p class="flex items-center gap-1.5 text-xs text-ink-faint italic">
								<ScanSearch class="size-3.5 shrink-0" />
								{note}
							</p>
						{/each}
						{#if body}
							<div class="prose-book !max-w-none text-[0.9rem]">
								<!-- eslint-disable-next-line svelte/no-at-html-tags — own vault's AI output -->
								{@html renderMarkdown(body)}
							</div>
						{/if}

						{#each turn.proposals as p (p.id)}
							<div
								class="rounded-xl border px-3 py-2.5 transition-opacity
								{p.status === 'discarded' ? 'border-line-soft opacity-50' : 'border-line bg-surface/60'}"
							>
								<div class="flex items-start gap-2">
									<span
										class="shrink-0 rounded-full border border-accent/40 bg-accent-soft px-2 py-0.5 text-[0.6875rem] font-medium text-accent-ink"
									>
										{TOOL_LABELS[p.tool] ?? p.tool}
									</span>
									<p class="min-w-0 flex-1 text-xs leading-relaxed text-ink">{p.summary}</p>
									{#if p.status === 'applied'}
										<span
											class="flex shrink-0 items-center gap-1 rounded-full border border-status-canon/40 bg-status-canon/10 px-2 py-0.5 text-[0.6875rem] font-medium text-status-canon"
										>
											<Check class="size-3" /> Applied
										</span>
									{:else if p.status === 'discarded'}
										<span class="shrink-0 text-[0.6875rem] text-ink-faint">Discarded</span>
									{:else if p.status === 'failed'}
										<span
											class="flex shrink-0 items-center gap-1 text-[0.6875rem] text-status-rejected"
										>
											<CircleAlert class="size-3" /> Failed
										</span>
									{/if}
								</div>

								{#if p.status === 'pending' || p.status === 'failed' || p.status === 'applying'}
									{#if p.tool === 'update_entity' && typeof p.args.content === 'string'}
										<!-- Diff against the saved content (or the open editor buffer),
										     computed at render time so edits landing mid-conversation show up. -->
										<div
											class="mt-2 max-h-72 overflow-y-auto rounded-lg border border-line-soft bg-inset/40 p-2 font-mono text-[0.6875rem] leading-relaxed"
										>
											{#each unifiedDiff(diffBase(String(p.args.id)), p.args.content) as row, k (k)}
												{#if row.kind === 'skip'}
													<p class="px-1 text-ink-faint">⋯ {row.count} unchanged lines</p>
												{:else}
													<p
														class="px-1 whitespace-pre-wrap
														{row.kind === 'add'
															? 'bg-status-canon/10 text-status-canon'
															: row.kind === 'del'
																? 'bg-status-rejected/10 text-status-rejected line-through decoration-status-rejected/40'
																: 'text-ink-muted'}"
													>
														{row.kind === 'add' ? '+' : row.kind === 'del' ? '−' : ' '}
														{row.text}
													</p>
												{/if}
											{/each}
										</div>
									{/if}

									{#if argRows(p).length}
										<dl class="mt-2 flex flex-col gap-0.5">
											{#each argRows(p) as [key, value] (key)}
												<div class="flex items-baseline gap-2 text-[0.6875rem]">
													<dt class="shrink-0 font-mono text-ink-faint">{key}</dt>
													<dd class="min-w-0 truncate text-ink-muted">{value}</dd>
												</div>
											{/each}
										</dl>
									{/if}
									{#if p.tool === 'create_entity' && typeof p.args.content === 'string' && p.args.content}
										<p class="mt-1.5 line-clamp-3 font-prose text-xs text-ink-muted italic">
											{p.args.content}
										</p>
									{/if}

									<div class="mt-2.5 flex items-center justify-end gap-1.5">
										<button
											type="button"
											onclick={() => (p.status = 'discarded')}
											disabled={p.status === 'applying'}
											class="rounded-lg px-2.5 py-1 text-xs text-ink-muted transition-colors hover:bg-inset hover:text-ink disabled:opacity-40"
										>
											Discard
										</button>
										<button
											type="button"
											onclick={() => apply(p)}
											disabled={p.status === 'applying'}
											class="flex items-center gap-1.5 rounded-lg bg-accent px-2.5 py-1 text-xs font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
										>
											{#if p.status === 'applying'}
												<LoaderCircle class="size-3 animate-spin" />
											{/if}
											Apply
										</button>
									</div>
								{/if}
							</div>
						{/each}
					</div>
				{/if}
			{/each}

			{#if busy}
				<p class="flex items-center gap-1.5 text-xs text-ink-faint">
					<LoaderCircle class="size-3.5 animate-spin" /> thinking…
				</p>
			{/if}
		</div>

		<form onsubmit={send} class="flex items-end gap-2 border-t border-line-soft px-3 py-3">
			<textarea
				bind:this={inputEl}
				bind:value={input}
				rows="2"
				placeholder="Ask about {effective.label}…"
				onkeydown={(e) => {
					if (e.key === 'Enter' && !e.shiftKey) {
						e.preventDefault();
						void send();
					}
				}}
				class="min-w-0 flex-1 resize-none rounded-lg border border-line bg-surface px-2.5 py-2 text-sm text-ink outline-none placeholder:text-ink-faint focus:border-accent"
			></textarea>
			<button
				type="submit"
				disabled={busy || !input.trim()}
				class="shrink-0 rounded-lg bg-accent p-2 text-paper transition-opacity hover:opacity-90 disabled:opacity-40"
				aria-label="Send"
			>
				<SendHorizontal class="size-4" />
			</button>
		</form>
	</aside>
{/if}
