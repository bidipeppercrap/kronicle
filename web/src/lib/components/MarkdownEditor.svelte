<script lang="ts">
	import type { Entity, ListResponse } from '$lib/types';
	import {
		autocompletion,
		type CompletionContext,
		type CompletionResult
	} from '@codemirror/autocomplete';
	import { defaultKeymap, history, historyKeymap, indentWithTab } from '@codemirror/commands';
	import { markdown, markdownLanguage } from '@codemirror/lang-markdown';
	import { syntaxHighlighting } from '@codemirror/language';
	import { EditorView, keymap, placeholder as cmPlaceholder } from '@codemirror/view';
	import { classHighlighter } from '@lezer/highlight';
	import { onMount } from 'svelte';

	let {
		value = $bindable(''),
		placeholder = 'Write…',
		onsave
	}: {
		value?: string;
		placeholder?: string;
		/** Called on Mod-S — the host decides what "save now" means. */
		onsave?: () => void;
	} = $props();

	let container: HTMLDivElement | undefined;
	let view: EditorView | undefined;

	/** `[[` opens entity autocomplete — wikilinks must never mean memorizing slugs. */
	async function wikilinkCompletions(ctx: CompletionContext): Promise<CompletionResult | null> {
		const match = ctx.matchBefore(/\[\[[^\][\n]*/);
		if (!match) return null;
		const query = match.text.slice(2).trim();

		try {
			const url = query
				? `/api/search?q=${encodeURIComponent(query)}&limit=12`
				: '/api/entities?limit=12';
			const res = await fetch(url);
			if (!res.ok) return null;
			const data = (await res.json()) as ListResponse<Entity>;
			if (!data.items.length) return null;

			return {
				from: match.from + 2,
				filter: false,
				options: data.items.map((e) => ({
					label: e.name,
					detail: `${e.type} · ${e.slug}`,
					apply: `${e.slug}]]`
				}))
			};
		} catch {
			return null;
		}
	}

	onMount(() => {
		view = new EditorView({
			parent: container,
			doc: value,
			extensions: [
				history(),
				markdown({ base: markdownLanguage }),
				syntaxHighlighting(classHighlighter),
				EditorView.lineWrapping,
				cmPlaceholder(placeholder),
				autocompletion({
					override: [wikilinkCompletions],
					activateOnTyping: true,
					icons: false
				}),
				keymap.of([
					{
						key: 'Mod-s',
						run: () => {
							onsave?.();
							return true;
						}
					},
					indentWithTab,
					...defaultKeymap,
					...historyKeymap
				]),
				EditorView.updateListener.of((update) => {
					if (update.docChanged) value = update.state.doc.toString();
				})
			]
		});
		return () => view?.destroy();
	});

	// External value changes (e.g. restoring a backup) flow into the document.
	$effect(() => {
		const next = value;
		if (view && next !== view.state.doc.toString()) {
			view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: next } });
		}
	});

	export function focus() {
		view?.focus();
	}
</script>

<div bind:this={container} class="h-full min-h-0"></div>
