<script lang="ts">
	import { beforeNavigate, goto } from '$app/navigation';
	import AiChatPanel from '$lib/components/AiChatPanel.svelte';
	import EntityPicker, { type PickedEntity } from '$lib/components/EntityPicker.svelte';
	import MarkdownEditor from '$lib/components/MarkdownEditor.svelte';
	import RevisionHistory from '$lib/components/RevisionHistory.svelte';
	import TypeIcon from '$lib/components/TypeIcon.svelte';
	import { METADATA_SUGGESTIONS, STATUS_DOT } from '$lib/entityMeta';
	import { timeAgo, wordCount } from '$lib/format';
	import { renderMarkdown } from '$lib/markdown';
	import { toast } from '$lib/toast.svelte';
	import {
		ENTITY_TYPES,
		MEDIA_TYPES,
		RELATIONSHIP_INVERSE_LABELS,
		RELATIONSHIP_LABELS,
		RELATIONSHIP_TYPES,
		STATUSES,
		STATUS_LABELS,
		TYPE_LABELS,
		type Entity,
		type EntityType,
		type Media,
		type MediaType,
		type Relationship,
		type RelationshipType,
		type Status
	} from '$lib/types';
	import {
		ArrowLeft,
		ArrowRightLeft,
		Check,
		CircleAlert,
		Eye,
		History,
		ImagePlus,
		LoaderCircle,
		PenLine,
		Plus,
		Sparkles,
		Trash2,
		X
	} from '@lucide/svelte';
	import { AlertDialog } from 'bits-ui';
	import { onMount, tick } from 'svelte';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	const entity = data.entity;
	const backupKey = `kronicle-draft-${entity.id}`;

	// ——— Editable state ———
	let name = $state(data.entity.name);
	let summary = $state(data.entity.summary);
	let content = $state(data.entity.content);
	let status = $state<Status>(data.entity.status);
	let type = $state<EntityType>(data.entity.type);
	let parentSel = $state<PickedEntity | null>(
		data.entity.parent_id && data.refs[data.entity.parent_id]
			? { ...data.refs[data.entity.parent_id] }
			: null
	);
	let metaRows = $state(
		Object.entries(data.entity.metadata).map(([key, value]) => ({
			key,
			value: typeof value === 'string' ? value : JSON.stringify(value)
		}))
	);
	let relationships = $state<Relationship[]>([...data.entity.relationships]);
	let refs = $state({ ...data.refs });

	// ——— Peek (rendered-Markdown preview, swapped in place of the editor) ———
	let peeking = $state(false);
	let editor = $state<{ focus: () => void }>();

	async function togglePeek() {
		peeking = !peeking;
		if (!peeking) {
			await tick();
			editor?.focus();
		}
	}

	// A restored revision arrives already saved server-side — sync the buffer
	// and the save machinery so autosave doesn't immediately re-PUT it.
	function handleRestored(updated: Entity) {
		content = updated.content;
		lastSaved = currentSnapshot();
		savedAt = updated.updated_at;
		saveState = 'saved';
		localStorage.removeItem(backupKey);
	}

	// ——— Save machinery ———
	interface Snapshot {
		name: string;
		summary: string;
		content: string;
		status: Status;
		type: EntityType;
		parent_id: string | null;
		metadata: string;
	}

	function parseMetaValue(raw: string): unknown {
		const v = raw.trim();
		if (v === 'true') return true;
		if (v === 'false') return false;
		if (v !== '' && !Number.isNaN(Number(v))) return Number(v);
		return raw;
	}

	function buildMetadata(): Record<string, unknown> {
		const out: Record<string, unknown> = {};
		for (const row of metaRows) {
			const key = row.key.trim();
			if (key) out[key] = parseMetaValue(row.value);
		}
		return out;
	}

	function currentSnapshot(): Snapshot {
		return {
			name: name.trim(),
			summary,
			content,
			status,
			type,
			parent_id: parentSel?.id ?? null,
			metadata: JSON.stringify(buildMetadata())
		};
	}

	let lastSaved = $state<Snapshot>({
		name: entity.name,
		summary: entity.summary,
		content: entity.content,
		status: entity.status,
		type: entity.type,
		parent_id: entity.parent_id,
		metadata: JSON.stringify(entity.metadata)
	});

	let saveState = $state<'saved' | 'dirty' | 'saving' | 'error'>('saved');
	let savedAt = $state<string>(entity.updated_at);
	let saveTimer: ReturnType<typeof setTimeout> | undefined;

	function snapshotsEqual(a: Snapshot, b: Snapshot): boolean {
		return (
			a.name === b.name &&
			a.summary === b.summary &&
			a.content === b.content &&
			a.status === b.status &&
			a.type === b.type &&
			a.parent_id === b.parent_id &&
			a.metadata === b.metadata
		);
	}

	async function save() {
		clearTimeout(saveTimer);
		const snap = currentSnapshot();
		if (snapshotsEqual(snap, lastSaved)) return;
		if (!snap.name) {
			saveState = 'error';
			return;
		}
		saveState = 'saving';

		// Partial PUT: only what changed (DESIGN.md decision 25).
		const payload: Record<string, unknown> = {};
		if (snap.name !== lastSaved.name) payload.name = snap.name;
		if (snap.summary !== lastSaved.summary) payload.summary = snap.summary;
		if (snap.content !== lastSaved.content) payload.content = snap.content;
		if (snap.status !== lastSaved.status) payload.status = snap.status;
		if (snap.type !== lastSaved.type) payload.type = snap.type;
		if (snap.parent_id !== lastSaved.parent_id) payload.parent_id = snap.parent_id;
		if (snap.metadata !== lastSaved.metadata) payload.metadata = JSON.parse(snap.metadata);

		try {
			const res = await fetch(`/api/entities/${entity.id}`, {
				method: 'PUT',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify(payload)
			});
			if (!res.ok) {
				const body = (await res.json().catch(() => null)) as { error?: string } | null;
				throw new Error(body?.error ?? `Save failed (${res.status})`);
			}
			const updated = (await res.json()) as Entity;
			lastSaved = snap;
			savedAt = updated.updated_at;
			saveState = snapshotsEqual(currentSnapshot(), snap) ? 'saved' : 'dirty';
			if (saveState === 'saved') localStorage.removeItem(backupKey);
		} catch (e) {
			saveState = 'error';
			toast(e instanceof Error ? e.message : 'Save failed', 'err');
		}
	}

	// Autosave: debounced PUT after ~2s idle + immediate localStorage backup.
	// Losing prose is this app's worst possible failure.
	$effect(() => {
		const snap = currentSnapshot();
		if (snapshotsEqual(snap, lastSaved)) return;
		saveState = 'dirty';
		try {
			localStorage.setItem(
				backupKey,
				JSON.stringify({
					content: snap.content,
					name: snap.name,
					summary: snap.summary,
					at: Date.now()
				})
			);
		} catch {
			// quota — the debounced PUT is still coming
		}
		clearTimeout(saveTimer);
		saveTimer = setTimeout(save, 2000);
		return () => clearTimeout(saveTimer);
	});

	beforeNavigate(() => {
		if (saveState === 'dirty') void save();
	});

	// ——— Unsaved-buffer backup recovery ———
	let backup = $state<{ content: string; name: string; summary: string; at: number } | null>(null);

	onMount(() => {
		try {
			const raw = localStorage.getItem(backupKey);
			if (!raw) return;
			const parsed = JSON.parse(raw) as typeof backup;
			if (parsed && parsed.content !== entity.content) backup = parsed;
			else localStorage.removeItem(backupKey);
		} catch {
			// corrupt backup — ignore
		}
	});

	function restoreBackup() {
		if (!backup) return;
		content = backup.content;
		name = backup.name || name;
		summary = backup.summary ?? summary;
		backup = null;
		toast('Backup restored — saving');
	}

	function discardBackup() {
		localStorage.removeItem(backupKey);
		backup = null;
	}

	// ——— Slug rename (server rewrites wikilinks atomically) ———
	let slugDraft = $state(data.entity.slug);
	let renaming = $state(false);

	async function renameSlug() {
		const next = slugDraft.trim();
		if (!next || next === entity.slug) return;
		renaming = true;
		try {
			const res = await fetch(`/api/entities/${entity.id}`, {
				method: 'PUT',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({ slug: next })
			});
			if (!res.ok) {
				const body = (await res.json().catch(() => null)) as { error?: string } | null;
				throw new Error(body?.error ?? 'Rename failed');
			}
			toast(`Renamed to [[${next}]] — wikilinks rewritten`);
			await goto(`/entities/${next}/edit`, { replaceState: true, invalidateAll: true });
		} catch (e) {
			toast(e instanceof Error ? e.message : 'Rename failed', 'err');
		} finally {
			renaming = false;
		}
	}

	// ——— Relationships ———
	let relType = $state<RelationshipType>('related_to');
	let relTarget = $state<PickedEntity | null>(null);
	let relLabel = $state('');
	let relOutgoing = $state(true);
	let relBusy = $state(false);

	async function addRelationship() {
		if (!relTarget || relBusy) return;
		relBusy = true;
		try {
			const res = await fetch('/api/relationships', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify({
					source_id: relOutgoing ? entity.id : relTarget.id,
					target_id: relOutgoing ? relTarget.id : entity.id,
					type: relType,
					label: relLabel.trim() || null
				})
			});
			const body = (await res.json().catch(() => null)) as
				| (Relationship & { error?: string })
				| null;
			if (!res.ok || !body) throw new Error(body?.error ?? 'Could not add relationship');
			relationships.push(body);
			refs[relTarget.id] = { ...relTarget, status: 'draft' };
			relTarget = null;
			relLabel = '';
		} catch (e) {
			toast(e instanceof Error ? e.message : 'Could not add relationship', 'err');
		} finally {
			relBusy = false;
		}
	}

	async function removeRelationship(id: string) {
		const res = await fetch(`/api/relationships/${id}`, { method: 'DELETE' });
		if (res.ok || res.status === 404) {
			relationships = relationships.filter((r) => r.id !== id);
		} else {
			toast('Could not remove relationship', 'err');
		}
	}

	function relParts(rel: Relationship) {
		const outgoing = rel.source_id === entity.id;
		const otherId = outgoing ? rel.target_id : rel.source_id;
		return {
			verb: outgoing ? RELATIONSHIP_LABELS[rel.type] : RELATIONSHIP_INVERSE_LABELS[rel.type],
			other: refs[otherId] ?? null,
			label: rel.label
		};
	}

	// ——— Media ———
	let mediaItems = $state<Media[]>([...data.entity.media]);
	let mediaType = $state<MediaType>('portrait');
	let uploading = $state(false);
	let fileInput = $state<HTMLInputElement | null>(null);

	async function uploadMedia(e: Event) {
		const input = e.currentTarget as HTMLInputElement;
		const file = input.files?.[0];
		if (!file || uploading) return;
		uploading = true;
		try {
			const form = new FormData();
			form.append('file', file);
			form.append('entity_id', entity.id);
			form.append('media_type', mediaType);
			const res = await fetch('/api/media', { method: 'POST', body: form });
			const body = (await res.json().catch(() => null)) as (Media & { error?: string }) | null;
			if (!res.ok || !body) throw new Error(body?.error ?? `Upload failed (${res.status})`);
			mediaItems.push(body);
			toast(`Uploaded ${mediaType}`);
		} catch (err) {
			toast(err instanceof Error ? err.message : 'Upload failed', 'err');
		} finally {
			uploading = false;
			input.value = '';
		}
	}

	async function removeMedia(id: string) {
		const res = await fetch(`/api/media/${id}`, { method: 'DELETE' });
		if (res.ok || res.status === 404) {
			mediaItems = mediaItems.filter((m) => m.id !== id);
		} else {
			toast('Could not delete media', 'err');
		}
	}

	// ——— Delete ———
	let deleting = $state(false);

	async function deleteEntity() {
		deleting = true;
		try {
			const res = await fetch(`/api/entities/${entity.id}`, { method: 'DELETE' });
			if (res.status === 204) {
				localStorage.removeItem(backupKey);
				toast(`Deleted “${entity.name}”`);
				await goto('/entities');
				return;
			}
			const body = (await res.json().catch(() => null)) as { error?: string } | null;
			throw new Error(body?.error ?? 'Delete failed');
		} catch (e) {
			toast(e instanceof Error ? e.message : 'Delete failed', 'err');
		} finally {
			deleting = false;
		}
	}

	const words = $derived(wordCount(content));
	const suggestions = $derived(
		METADATA_SUGGESTIONS[type].filter((k) => !metaRows.some((r) => r.key === k))
	);

	// ——— AI chat ———
	let chatOpen = $state(false);
	const chatCurrent = $derived({ content, summary });

	/**
	 * Applied update_entity proposals for this entity merge into the open
	 * buffer and ride the normal autosave — a direct PUT would race it.
	 */
	function applyAiUpdate(fields: Record<string, unknown>) {
		if (typeof fields.name === 'string') name = fields.name;
		if (typeof fields.summary === 'string') summary = fields.summary;
		if (typeof fields.content === 'string') content = fields.content;
		if (fields.metadata && typeof fields.metadata === 'object') {
			metaRows = Object.entries(fields.metadata as Record<string, unknown>).map(
				([key, value]) => ({
					key,
					value: typeof value === 'string' ? value : JSON.stringify(value)
				})
			);
		}
	}
</script>

<svelte:head>
	<title>Editing {name || entity.name} · Kronicle</title>
</svelte:head>

<svelte:window
	onbeforeunload={(e) => {
		if (saveState === 'dirty' || saveState === 'saving') e.preventDefault();
	}}
	onkeydown={(e) => {
		if (!(e.ctrlKey || e.metaKey)) return;
		if (e.key === 'e') {
			e.preventDefault();
			togglePeek();
		} else if (e.key === 's' && peeking) {
			// The editor's own Mod-S keymap can't fire while it's hidden.
			e.preventDefault();
			save();
		}
	}}
/>

<div class="flex min-h-dvh flex-col">
	<!-- Toolbar -->
	<div
		class="sticky top-0 z-30 flex items-center gap-3 border-b border-line-soft bg-paper/90 px-4 py-2.5 backdrop-blur"
	>
		<a
			href="/entities/{entity.slug}"
			class="flex shrink-0 items-center gap-1 rounded-lg p-1.5 text-sm text-ink-muted transition-colors hover:bg-surface hover:text-ink"
			aria-label="Back to page"
		>
			<ArrowLeft class="size-4" />
		</a>
		<input
			bind:value={name}
			placeholder="Name"
			class="min-w-0 flex-1 bg-transparent font-prose text-xl font-semibold text-ink outline-none placeholder:text-ink-faint"
		/>
		<span class="flex shrink-0 items-center gap-1.5 text-xs text-ink-faint">
			{#if saveState === 'saving'}
				<LoaderCircle class="size-3.5 animate-spin" /> saving…
			{:else if saveState === 'dirty'}
				<span class="size-1.5 rounded-full bg-status-stub"></span> unsaved
			{:else if saveState === 'error'}
				<CircleAlert class="size-3.5 text-status-rejected" />
				<span class="text-status-rejected">{name.trim() ? 'save failed' : 'name required'}</span>
			{:else}
				<Check class="size-3.5 text-status-canon" /> saved {timeAgo(savedAt)}
			{/if}
		</span>
		<button
			type="button"
			onclick={togglePeek}
			aria-pressed={peeking}
			aria-label={peeking ? 'Back to writing' : 'Preview rendered Markdown'}
			title="{peeking ? 'Write' : 'Peek'} (Ctrl+E)"
			class="flex shrink-0 items-center gap-1.5 rounded-lg border px-2.5 py-1.5 text-sm transition-colors hover:border-accent hover:text-accent-ink {peeking
				? 'border-accent bg-accent-soft text-accent-ink'
				: 'border-line bg-surface text-ink-muted'}"
		>
			{#if peeking}
				<PenLine class="size-4" />
			{:else}
				<Eye class="size-4" />
			{/if}
		</button>
		<button
			type="button"
			onclick={() => (chatOpen = !chatOpen)}
			class="flex shrink-0 items-center gap-1.5 rounded-lg border border-line bg-surface px-2.5 py-1.5 text-sm text-ink-muted transition-colors hover:border-accent hover:text-accent-ink"
			aria-label="AI chat"
		>
			<Sparkles class="size-4" />
		</button>
		<button
			type="button"
			onclick={save}
			class="shrink-0 rounded-lg bg-accent px-3 py-1.5 text-sm font-medium text-paper transition-opacity hover:opacity-90"
		>
			Save
		</button>
	</div>

	{#if backup}
		<div
			class="flex flex-wrap items-center gap-3 border-b border-status-stub/40 bg-accent-soft px-4 py-2.5 text-sm text-ink"
		>
			<History class="size-4 shrink-0 text-status-stub" />
			<span class="min-w-0 flex-1">
				An unsaved local backup from {timeAgo(new Date(backup.at).toISOString())} differs from this
				page.
			</span>
			<button
				type="button"
				onclick={restoreBackup}
				class="rounded-lg border border-line bg-surface px-2.5 py-1 text-xs font-medium hover:border-accent"
			>
				Restore it
			</button>
			<button
				type="button"
				onclick={discardBackup}
				class="rounded-lg px-2.5 py-1 text-xs text-ink-muted hover:text-ink"
			>
				Discard
			</button>
		</div>
	{/if}

	<div class="flex min-h-0 flex-1 flex-col lg:flex-row">
		<!-- The manuscript -->
		<div class="min-w-0 flex-1">
			<!-- Hidden, not unmounted, while peeking — keeps CodeMirror's undo history and cursor. -->
			<div class={peeking ? 'hidden' : 'contents'}>
				<MarkdownEditor
					bind:this={editor}
					bind:value={content}
					placeholder="Draft in Markdown. Type [[ to link an entity."
					onsave={save}
				/>
			</div>
			{#if peeking}
				{#if content.trim()}
					<div class="prose-book animate-rise mx-auto max-w-[68ch] px-6 py-6">
						{@html renderMarkdown(content)}
					</div>
				{:else}
					<p class="px-6 py-6 text-center text-sm text-ink-faint">Nothing to preview yet.</p>
				{/if}
			{/if}
			<p
				class="px-6 pb-4 text-center text-xs text-ink-faint lg:pl-[max(1.5rem,calc((100%-72ch)/2))] lg:text-left"
			>
				{words.toLocaleString()} words
			</p>
		</div>

		<!-- Margin notes: metadata, structure, connections -->
		<aside
			class="w-full shrink-0 border-t border-line-soft bg-inset/40 px-4 py-5 lg:w-80 lg:border-t-0 lg:border-l"
		>
			<div class="flex flex-col gap-6 text-sm lg:sticky lg:top-16">
				<section>
					<h3 class="mb-1.5 text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase">
						Summary
					</h3>
					<textarea
						bind:value={summary}
						rows="3"
						placeholder="One or two sentences for cards and lists."
						class="w-full resize-y rounded-lg border border-line bg-surface px-2.5 py-2 font-prose text-sm text-ink outline-none placeholder:text-ink-faint focus:border-accent"
					></textarea>
				</section>

				<section>
					<h3 class="mb-1.5 text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase">
						Status
					</h3>
					<div class="grid grid-cols-2 gap-1.5">
						{#each STATUSES as s (s)}
							<button
								type="button"
								onclick={() => (status = s)}
								class="flex items-center gap-1.5 rounded-lg border px-2 py-1.5 text-xs transition-colors
								{status === s
									? 'border-accent bg-accent-soft font-medium text-accent-ink'
									: 'border-line text-ink-muted hover:border-ink-faint hover:text-ink'}"
							>
								<span class="size-1.5 rounded-full {STATUS_DOT[s]}"></span>
								{STATUS_LABELS[s]}
							</button>
						{/each}
					</div>
				</section>

				<section class="grid grid-cols-2 gap-3">
					<div>
						<h3 class="mb-1.5 text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase">
							Type
						</h3>
						<select
							bind:value={type}
							class="w-full rounded-lg border border-line bg-surface px-2 py-1.5 text-sm text-ink outline-none focus:border-accent"
						>
							{#each ENTITY_TYPES as t (t)}
								<option value={t}>{TYPE_LABELS[t]}</option>
							{/each}
						</select>
					</div>
					<div>
						<h3 class="mb-1.5 text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase">
							Parent
						</h3>
						<EntityPicker bind:selected={parentSel} placeholder="None" exclude={[entity.id]} />
					</div>
				</section>

				<section>
					<h3 class="mb-1.5 text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase">
						Details
					</h3>
					<div class="flex flex-col gap-1.5">
						{#each metaRows as row, i (i)}
							<div class="flex items-center gap-1.5">
								<input
									bind:value={row.key}
									placeholder="field"
									class="w-2/5 rounded-lg border border-line bg-surface px-2 py-1.5 font-mono text-xs text-ink outline-none placeholder:text-ink-faint focus:border-accent"
								/>
								<input
									bind:value={row.value}
									placeholder="value"
									class="min-w-0 flex-1 rounded-lg border border-line bg-surface px-2 py-1.5 text-xs text-ink outline-none placeholder:text-ink-faint focus:border-accent"
								/>
								<button
									type="button"
									onclick={() => metaRows.splice(i, 1)}
									class="shrink-0 rounded p-1 text-ink-faint transition-colors hover:text-status-rejected"
									aria-label="Remove field"
								>
									<X class="size-3.5" />
								</button>
							</div>
						{/each}
					</div>
					<div class="mt-2 flex flex-wrap gap-1.5">
						{#each suggestions as key (key)}
							<button
								type="button"
								onclick={() => metaRows.push({ key, value: '' })}
								class="rounded-full border border-dashed border-line px-2 py-0.5 font-mono text-[0.6875rem] text-ink-faint transition-colors hover:border-accent hover:text-accent-ink"
							>
								+ {key}
							</button>
						{/each}
						<button
							type="button"
							onclick={() => metaRows.push({ key: '', value: '' })}
							class="rounded-full border border-dashed border-line px-2 py-0.5 text-[0.6875rem] text-ink-faint transition-colors hover:border-accent hover:text-accent-ink"
						>
							<Plus class="inline size-3" /> field
						</button>
					</div>
				</section>

				<section>
					<h3 class="mb-1.5 text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase">
						Relationships
					</h3>
					{#if relationships.length}
						<ul class="mb-3 flex flex-col gap-1">
							{#each relationships as rel (rel.id)}
								{@const parts = relParts(rel)}
								<li class="group flex items-center gap-1.5 leading-snug">
									<span class="min-w-0 flex-1">
										<span class="text-ink-faint">{parts.verb}</span>
										{#if parts.other}
											<a
												href="/entities/{parts.other.slug}"
												class="text-accent-ink hover:underline">{parts.other.name}</a
											>
										{:else}
											<span class="text-ink-muted">?</span>
										{/if}
										{#if parts.label}
											<span class="text-xs text-ink-faint">— {parts.label}</span>
										{/if}
									</span>
									<button
										type="button"
										onclick={() => removeRelationship(rel.id)}
										class="shrink-0 rounded p-1 text-ink-faint opacity-0 transition-all group-hover:opacity-100 hover:text-status-rejected"
										aria-label="Remove relationship"
									>
										<X class="size-3.5" />
									</button>
								</li>
							{/each}
						</ul>
					{/if}
					<div class="flex flex-col gap-1.5 rounded-lg border border-line-soft bg-surface/60 p-2">
						<div class="flex items-center gap-1.5">
							<button
								type="button"
								onclick={() => (relOutgoing = !relOutgoing)}
								title={relOutgoing ? 'This entity is the source' : 'This entity is the target'}
								class="flex shrink-0 items-center gap-1 rounded-lg border border-line px-2 py-1.5 text-xs text-ink-muted transition-colors hover:border-accent hover:text-accent-ink"
							>
								<ArrowRightLeft class="size-3" />
								{relOutgoing ? 'this →' : '→ this'}
							</button>
							<select
								bind:value={relType}
								class="min-w-0 flex-1 rounded-lg border border-line bg-surface px-2 py-1.5 text-xs text-ink outline-none focus:border-accent"
							>
								{#each RELATIONSHIP_TYPES as rt (rt)}
									<option value={rt}>{RELATIONSHIP_LABELS[rt]}</option>
								{/each}
							</select>
						</div>
						<EntityPicker bind:selected={relTarget} exclude={[entity.id]} />
						<div class="flex items-center gap-1.5">
							<input
								bind:value={relLabel}
								placeholder="label (optional)"
								class="min-w-0 flex-1 rounded-lg border border-line bg-surface px-2 py-1.5 text-xs text-ink outline-none placeholder:text-ink-faint focus:border-accent"
							/>
							<button
								type="button"
								onclick={addRelationship}
								disabled={!relTarget || relBusy}
								class="shrink-0 rounded-lg bg-accent px-2.5 py-1.5 text-xs font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-40"
							>
								Add
							</button>
						</div>
					</div>
				</section>

				<section>
					<h3 class="mb-1.5 text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase">
						Media
					</h3>
					{#if mediaItems.length}
						<div class="mb-2 grid grid-cols-3 gap-2">
							{#each mediaItems as item (item.id)}
								<div class="group relative">
									<img
										src="/api/media/{item.id}/file"
										alt={item.alt_text ?? item.media_type}
										title={item.media_type}
										loading="lazy"
										class="aspect-square w-full rounded-lg border border-line-soft object-cover"
									/>
									<button
										type="button"
										onclick={() => removeMedia(item.id)}
										class="absolute top-1 right-1 hidden rounded bg-paper/85 p-0.5 text-ink-faint transition-colors group-hover:block hover:text-status-rejected"
										aria-label="Delete {item.media_type}"
									>
										<X class="size-3.5" />
									</button>
								</div>
							{/each}
						</div>
					{/if}
					<div class="flex items-center gap-1.5">
						<select
							bind:value={mediaType}
							class="min-w-0 flex-1 rounded-lg border border-line bg-surface px-2 py-1.5 text-xs text-ink outline-none focus:border-accent"
						>
							{#each MEDIA_TYPES as mt (mt)}
								<option value={mt}>{mt}</option>
							{/each}
						</select>
						<button
							type="button"
							onclick={() => fileInput?.click()}
							disabled={uploading}
							class="flex shrink-0 items-center gap-1.5 rounded-lg border border-line px-2.5 py-1.5 text-xs font-medium text-ink transition-colors hover:border-accent hover:text-accent-ink disabled:opacity-50"
						>
							{#if uploading}
								<LoaderCircle class="size-3.5 animate-spin" />
							{:else}
								<ImagePlus class="size-3.5" />
							{/if}
							Upload
						</button>
						<input
							type="file"
							accept="image/*"
							hidden
							bind:this={fileInput}
							onchange={uploadMedia}
						/>
					</div>
				</section>

				<section>
					<h3 class="mb-1.5 text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase">
						Slug
					</h3>
					<div class="flex items-center gap-1.5">
						<input
							bind:value={slugDraft}
							class="min-w-0 flex-1 rounded-lg border border-line bg-surface px-2.5 py-1.5 font-mono text-xs text-ink outline-none focus:border-accent"
						/>
						{#if slugDraft.trim() !== entity.slug}
							<button
								type="button"
								onclick={renameSlug}
								disabled={renaming}
								class="shrink-0 rounded-lg border border-line px-2.5 py-1.5 text-xs font-medium text-ink transition-colors hover:border-accent hover:text-accent-ink disabled:opacity-50"
							>
								Rename
							</button>
						{/if}
					</div>
					<p class="mt-1.5 text-xs leading-snug text-ink-faint">
						Renaming rewrites every [[{entity.slug}]] across the vault — links never dangle.
					</p>
				</section>

				<RevisionHistory entityId={entity.id} onrestored={handleRestored} />

				<section class="border-t border-line-soft pt-4">
					<AlertDialog.Root>
						<AlertDialog.Trigger
							class="flex items-center gap-1.5 rounded-lg px-2 py-1.5 text-xs text-status-rejected transition-colors hover:bg-status-rejected/10"
						>
							<Trash2 class="size-3.5" /> Delete this entity
						</AlertDialog.Trigger>
						<AlertDialog.Portal>
							<AlertDialog.Overlay
								class="fixed inset-0 z-50 bg-[oklch(0.2_0.015_70/0.45)] backdrop-blur-[2px]"
							/>
							<AlertDialog.Content
								class="fixed top-1/2 left-1/2 z-50 w-[min(26rem,calc(100vw-2rem))] -translate-x-1/2 -translate-y-1/2 animate-rise rounded-xl border border-line bg-surface p-6 shadow-2xl"
							>
								<AlertDialog.Title class="font-prose text-lg font-semibold text-ink">
									Delete “{entity.name}”?
								</AlertDialog.Title>
								<AlertDialog.Description class="mt-2 text-sm leading-relaxed text-ink-muted">
									This removes the entity, its relationships, and its media. Prose is gone for
									good — deletion is the one thing revisions can't undo. Rejected ideas can be
									kept as <em>rejected</em> instead.
								</AlertDialog.Description>
								<div class="mt-5 flex justify-end gap-2">
									<AlertDialog.Cancel
										class="rounded-lg border border-line px-3 py-1.5 text-sm text-ink transition-colors hover:bg-inset"
									>
										Keep it
									</AlertDialog.Cancel>
									<AlertDialog.Action
										disabled={deleting}
										onclick={deleteEntity}
										class="rounded-lg bg-status-rejected px-3 py-1.5 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
									>
										Delete
									</AlertDialog.Action>
								</div>
							</AlertDialog.Content>
						</AlertDialog.Portal>
					</AlertDialog.Root>
				</section>

				<p class="flex items-center gap-1.5 text-xs text-ink-faint">
					<TypeIcon {type} class="size-3.5" />
					Autosaves 2s after you pause. ⌘S saves now.
				</p>
			</div>
		</aside>
	</div>
</div>

<AiChatPanel
	entity={{ id: entity.id, name: entity.name }}
	current={chatCurrent}
	bind:open={chatOpen}
	onLocalUpdate={applyAiUpdate}
/>
