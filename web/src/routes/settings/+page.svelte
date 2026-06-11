<script lang="ts">
	import { toast } from '$lib/toast.svelte';
	import type { AiSettings } from '$lib/types';
	import { KeyRound, LoaderCircle, Sparkles, Trash2 } from '@lucide/svelte';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	let ai = $state<AiSettings>(data.ai);
	let apiKey = $state('');
	let apiUrl = $state(data.ai.api_url ?? '');
	let model = $state(data.ai.model ?? '');
	let saving = $state(false);

	async function save(body: Record<string, string>): Promise<boolean> {
		saving = true;
		try {
			const res = await fetch('/api/settings/ai', {
				method: 'PUT',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify(body)
			});
			const json = (await res.json().catch(() => null)) as
				| (AiSettings & { error?: string })
				| null;
			if (!res.ok) throw new Error(json?.error ?? `Save failed (${res.status})`);
			ai = json as AiSettings;
			apiUrl = ai.api_url ?? '';
			model = ai.model ?? '';
			toast('AI settings saved');
			return true;
		} catch (err) {
			toast(err instanceof Error ? err.message : 'Save failed', 'err');
			return false;
		} finally {
			saving = false;
		}
	}

	async function submit(e: Event) {
		e.preventDefault();
		const body: Record<string, string> = { api_url: apiUrl.trim(), model: model.trim() };
		// Blank key field means "leave the stored key alone", not "clear it" —
		// the field never echoes the saved key back, so it is usually blank.
		if (apiKey.trim()) body.api_key = apiKey.trim();
		if (await save(body)) apiKey = '';
	}

	async function clearKey() {
		await save({ api_key: '' });
		apiKey = '';
	}
</script>

<svelte:head>
	<title>Settings · Kronicle</title>
</svelte:head>

<div class="mx-auto w-full max-w-3xl px-4 py-8 sm:px-6 md:py-12">
	<h1 class="mb-1 font-prose text-2xl font-semibold tracking-tight text-ink">Settings</h1>
	<p class="mb-8 text-sm text-ink-muted">Vault configuration — stored in the database, not env vars.</p>

	<section>
		<div class="mb-2 flex items-center gap-2 px-3">
			<Sparkles class="size-4 text-accent-ink" />
			<h2 class="font-prose text-lg font-semibold text-ink">AI provider</h2>
			<span class="text-xs text-ink-faint">
				any OpenAI-compatible chat-completions endpoint — DeepSeek, OpenAI, OpenRouter, Claude, local…
			</span>
		</div>

		<form onsubmit={submit} class="flex flex-col gap-4 rounded-xl border border-line bg-surface/60 px-4 py-4">
			<div>
				<label
					for="ai-key"
					class="mb-1.5 block text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase"
				>
					API key
				</label>
				<div class="flex items-center gap-2">
					<input
						id="ai-key"
						type="password"
						bind:value={apiKey}
						placeholder={ai.api_key_set ? `saved (${ai.api_key_hint})` : 'sk-…'}
						autocomplete="off"
						class="min-w-0 flex-1 rounded-lg border border-line bg-paper px-2.5 py-2 font-mono text-sm text-ink outline-none placeholder:font-sans placeholder:text-ink-faint focus:border-accent"
					/>
					{#if ai.api_key_source === 'settings'}
						<button
							type="button"
							onclick={clearKey}
							disabled={saving}
							class="flex shrink-0 items-center gap-1.5 rounded-lg px-2.5 py-2 text-xs text-ink-muted transition-colors hover:bg-inset hover:text-status-rejected disabled:opacity-40"
						>
							<Trash2 class="size-3.5" /> Clear
						</button>
					{/if}
				</div>
				<p class="mt-1.5 flex items-center gap-1.5 text-xs text-ink-faint">
					<KeyRound class="size-3 shrink-0" />
					{#if ai.api_key_source === 'settings'}
						A key is saved here{ai.api_key_hint ? ` (${ai.api_key_hint})` : ''}. Paste a new one to
						replace it; it's stored in the database and never shown again in full.
					{:else if ai.api_key_source === 'env'}
						Currently using the Worker's <code class="font-mono">DEEPSEEK_API_KEY</code> env var.
						Saving a key here overrides it.
					{:else}
						No key configured — AI chat is off until you add one.
					{/if}
				</p>
			</div>

			<div class="grid gap-4 sm:grid-cols-2">
				<div>
					<label
						for="ai-url"
						class="mb-1.5 block text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase"
					>
						API URL
					</label>
					<input
						id="ai-url"
						type="url"
						bind:value={apiUrl}
						placeholder="https://api.deepseek.com"
						class="w-full rounded-lg border border-line bg-paper px-2.5 py-2 font-mono text-sm text-ink outline-none placeholder:text-ink-faint focus:border-accent"
					/>
				</div>
				<div>
					<label
						for="ai-model"
						class="mb-1.5 block text-[0.6875rem] font-medium tracking-wider text-ink-faint uppercase"
					>
						Model
					</label>
					<input
						id="ai-model"
						bind:value={model}
						placeholder="deepseek-chat"
						class="w-full rounded-lg border border-line bg-paper px-2.5 py-2 font-mono text-sm text-ink outline-none placeholder:text-ink-faint focus:border-accent"
					/>
				</div>
			</div>
			<p class="text-xs text-ink-faint">
				The Worker appends <code class="font-mono">/chat/completions</code> to the API URL, so
				include the provider's version prefix: <code class="font-mono">https://api.openai.com/v1</code>,
				<code class="font-mono">https://openrouter.ai/api/v1</code>,
				<code class="font-mono">https://api.anthropic.com/v1</code>. Blank fields fall back to the
				Worker's env defaults (DeepSeek).
			</p>

			<div class="flex justify-end">
				<button
					type="submit"
					disabled={saving}
					class="flex items-center gap-1.5 rounded-lg bg-accent px-3 py-1.5 text-sm font-medium text-paper transition-opacity hover:opacity-90 disabled:opacity-50"
				>
					{#if saving}<LoaderCircle class="size-3.5 animate-spin" />{/if}
					Save
				</button>
			</div>
		</form>
	</section>
</div>
