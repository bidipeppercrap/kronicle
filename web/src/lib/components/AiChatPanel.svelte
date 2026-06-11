<script lang="ts">
	import { invalidateAll } from '$app/navigation';
	import { unifiedDiff } from '$lib/diff';
	import { renderMarkdown } from '$lib/markdown';
	import { toast } from '$lib/toast.svelte';
	import {
		Check,
		CircleAlert,
		LoaderCircle,
		ScanSearch,
		SendHorizontal,
		Sparkles,
		X
	} from '@lucide/svelte';

	/**
	 * Per-entity AI chat (DESIGN.md, AI Chat). Stateless on the server: this
	 * component holds the whole conversation and sends it every turn. Write
	 * tools arrive as proposals; nothing changes until Apply, which goes
	 * through the normal REST save path.
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
		proposals: Proposal[];
		reading: string[];
	}

	let {
		entity,
		current,
		open = $bindable(false),
		onLocalUpdate
	}: {
		entity: { id: string; name: string };
		/** Live buffer the content diff is rendered against (DESIGN.md). */
		current: { content: string; summary: string };
		open?: boolean;
		/**
		 * Editor hook: apply an update to this entity by merging into the
		 * open buffer (autosave persists it) instead of PUTting around it.
		 */
		onLocalUpdate?: (fields: Record<string, unknown>) => void;
	} = $props();

	const TOOL_LABELS: Record<string, string> = {
		update_entity: 'Edit',
		create_entity: 'New entity',
		add_relationship: 'Add relationship',
		remove_relationship: 'Remove relationship'
	};

	let turns = $state<Turn[]>([]);
	let input = $state('');
	let busy = $state(false);
	let scrollEl = $state<HTMLElement | null>(null);

	// Follow the stream: keep the transcript pinned to the bottom.
	$effect(() => {
		void turns.length;
		void turns.at(-1)?.text;
		void turns.at(-1)?.proposals.length;
		if (scrollEl) scrollEl.scrollTop = scrollEl.scrollHeight;
	});

	/**
	 * Wire-format history: plain {role, content}. Proposals and their
	 * outcomes are flattened into the assistant turn so the model knows
	 * next turn what landed — the server remembers nothing (DESIGN.md).
	 */
	function wireHistory(): { role: string; content: string }[] {
		const msgs: { role: string; content: string }[] = [];
		for (const t of turns) {
			if (t.role === 'user') {
				msgs.push({ role: 'user', content: t.text });
				continue;
			}
			let content = t.text;
			for (const p of t.proposals) {
				const outcome =
					p.status === 'applied' ? 'applied' : p.status === 'discarded' ? 'discarded' : 'pending';
				content += `\n\n[Proposed ${p.id}: ${p.summary} — ${outcome}]`;
			}
			if (content.trim()) msgs.push({ role: 'assistant', content: content.trim() });
		}
		return msgs;
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
				turn.proposals.push({ ...(data as unknown as Proposal), status: 'pending' });
			}
		} else if (event === 'error') {
			toast(String(data.message ?? 'AI chat failed'), 'err');
		}
	}

	async function send(e?: Event) {
		e?.preventDefault();
		const text = input.trim();
		if (!text || busy) return;
		input = '';
		turns.push({ role: 'user', text, proposals: [], reading: [] });
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
				body: JSON.stringify({ entity_id: entity.id, messages: history })
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

	/** Apply = dumb dispatch through the normal REST save path (DESIGN.md). */
	async function apply(p: Proposal) {
		if (p.status === 'applying' || p.status === 'applied') return;
		p.status = 'applying';
		try {
			if (p.tool === 'update_entity') {
				const { id, ...fields } = p.args as { id: string } & Record<string, unknown>;
				if (onLocalUpdate && id === entity.id) {
					onLocalUpdate(fields);
				} else {
					await rest('PUT', `/api/entities/${id}`, fields);
				}
			} else if (p.tool === 'create_entity') {
				await rest('POST', '/api/entities', p.args);
			} else if (p.tool === 'add_relationship') {
				await rest('POST', '/api/relationships', p.args);
			} else if (p.tool === 'remove_relationship') {
				await rest('DELETE', `/api/relationships/${p.args.id}`);
			} else {
				throw new Error(`Unknown proposal tool: ${p.tool}`);
			}
			p.status = 'applied';
			toast(`Applied — ${p.summary}`);
			if (!onLocalUpdate) await invalidateAll();
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
				<p class="truncate text-sm font-medium text-ink">Chat — {entity.name}</p>
				<p class="text-[0.6875rem] text-ink-faint">
					Proposals only. Nothing changes until you apply it.
				</p>
			</div>
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
				<p class="m-auto max-w-[26ch] text-center text-sm text-ink-faint italic">
					Discuss {entity.name} — ask for a rewrite and you'll get a diff to apply or discard.
					Closing the panel ends the conversation.
				</p>
			{/if}

			{#each turns as turn, i (i)}
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
						{#if turn.text}
							<div class="prose-book !max-w-none text-[0.9rem]">
								<!-- eslint-disable-next-line svelte/no-at-html-tags — own vault's AI output -->
								{@html renderMarkdown(turn.text)}
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
										<!-- Diff against the current buffer, computed at render
										     time so edits landing mid-conversation show up. -->
										<div
											class="mt-2 max-h-72 overflow-y-auto rounded-lg border border-line-soft bg-inset/40 p-2 font-mono text-[0.6875rem] leading-relaxed"
										>
											{#each unifiedDiff(current.content, p.args.content) as row, k (k)}
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
				bind:value={input}
				rows="2"
				placeholder="Discuss {entity.name}…"
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
