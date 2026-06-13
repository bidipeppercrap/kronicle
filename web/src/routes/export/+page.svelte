<script lang="ts">
	import { toast } from '$lib/toast.svelte';
	import { Download, LoaderCircle, TriangleAlert, Upload } from '@lucide/svelte';

	let file = $state<File | null>(null);
	let replace = $state(false);
	let importing = $state(false);

	function pick(e: Event) {
		file = (e.target as HTMLInputElement).files?.[0] ?? null;
	}

	async function runImport(e: Event) {
		e.preventDefault();
		if (!file) return;
		importing = true;
		try {
			const res = await fetch(`/api/import?replace=${replace}`, { method: 'POST', body: file });
			const json = (await res.json().catch(() => null)) as
				| { imported?: Record<string, number>; error?: string }
				| null;
			if (!res.ok) throw new Error(json?.error ?? `Import failed (${res.status})`);
			const c = json?.imported;
			toast(
				c
					? `Restored ${c.entities} entities, ${c.relationships} relationships, ${c.media} media`
					: 'Import complete'
			);
			file = null;
			replace = false;
			(document.getElementById('import-file') as HTMLInputElement).value = '';
		} catch (err) {
			toast(err instanceof Error ? err.message : 'Import failed', 'err');
		} finally {
			importing = false;
		}
	}
</script>

<svelte:head>
	<title>Backup · Kronicle</title>
</svelte:head>

<div class="mx-auto w-full max-w-3xl px-4 py-8 sm:px-6 md:py-12">
	<h1 class="mb-1 font-prose text-2xl font-semibold tracking-tight text-ink">Backup &amp; portability</h1>
	<p class="mb-8 text-sm text-ink-muted">
		Download your whole vault as a zip, or restore one. The backup holds a Markdown file per entity
		(YAML frontmatter + prose, ready for Obsidian) plus a lossless <code class="font-mono">kronicle.json</code>
		and every media file.
	</p>

	<section class="mb-8">
		<div class="mb-2 flex items-center gap-2 px-3">
			<Download class="size-4 text-accent-ink" />
			<h2 class="font-prose text-lg font-semibold text-ink">Export</h2>
		</div>
		<div class="flex flex-col gap-4 rounded-xl border border-line bg-surface/60 px-4 py-4">
			<p class="text-sm text-ink-muted">
				Downloads <code class="font-mono">kronicle-backup-&lt;date&gt;.zip</code>. The AI provider key
				is never included.
			</p>
			<div>
				<a
					href="/api/export"
					download="kronicle-backup.zip"
					class="inline-flex items-center gap-1.5 rounded-lg bg-accent px-3 py-1.5 text-sm font-medium text-paper transition-opacity hover:opacity-90"
				>
					<Download class="size-3.5" /> Download backup
				</a>
			</div>
		</div>
	</section>

	<section>
		<div class="mb-2 flex items-center gap-2 px-3">
			<Upload class="size-4 text-accent-ink" />
			<h2 class="font-prose text-lg font-semibold text-ink">Import</h2>
		</div>
		<form onsubmit={runImport} class="flex flex-col gap-4 rounded-xl border border-line bg-surface/60 px-4 py-4">
			<div>
				<label
					for="import-file"
					class="mb-1.5 block text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase"
				>
					Backup zip
				</label>
				<input
					id="import-file"
					type="file"
					accept=".zip,application/zip"
					onchange={pick}
					class="w-full text-sm text-ink-muted file:mr-3 file:rounded-lg file:border file:border-line file:bg-paper file:px-3 file:py-1.5 file:text-sm file:font-medium file:text-ink hover:file:border-accent"
				/>
			</div>

			<label class="flex items-start gap-2.5 text-sm text-ink">
				<input type="checkbox" bind:checked={replace} class="mt-0.5 accent-accent" />
				<span>
					Replace existing vault
					<span class="mt-0.5 flex items-center gap-1.5 text-xs text-ink-faint">
						<TriangleAlert class="size-3 shrink-0" />
						Wipes all current entities, relationships, revisions, and media first. Required when the
						vault isn't already empty.
					</span>
				</span>
			</label>

			<div class="flex justify-end">
				<button
					type="submit"
					disabled={importing || !file}
					class="flex items-center gap-1.5 rounded-lg bg-accent px-3 py-1.5 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
				>
					{#if importing}<LoaderCircle class="size-3.5 animate-spin" />{/if}
					Restore from backup
				</button>
			</div>
		</form>
	</section>
</div>
