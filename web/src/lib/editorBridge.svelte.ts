/**
 * Bridge between the open editor and the global route-aware chat panel.
 *
 * The chat lives in the app shell, not inside the editor (DESIGN.md, route-aware
 * chat). So when it proposes an edit to the entity the writer happens to have
 * open in the editor, applying it must merge into the live buffer — which rides
 * autosave — instead of PUTting around it and clobbering unsaved prose. The
 * editor registers itself here on mount and clears on teardown; everywhere else
 * the panel falls back to the normal REST + refetch path.
 */
class EditorBridge {
	/** The entity currently open in the editor, or null when no editor is mounted. */
	entityId = $state<string | null>(null);
	/** The editor's live buffer, kept in sync so the chat can diff against it. */
	current = $state<{ content: string; summary: string } | null>(null);
	/** Merge an applied update_entity proposal into the open buffer. */
	applyUpdate: ((fields: Record<string, unknown>) => void) | null = null;

	open(entityId: string, applyUpdate: (fields: Record<string, unknown>) => void) {
		this.entityId = entityId;
		this.applyUpdate = applyUpdate;
	}

	setCurrent(current: { content: string; summary: string }) {
		this.current = current;
	}

	close(entityId: string) {
		// Only clear if we still own the link — guards against a new editor
		// mounting before the previous one's teardown runs.
		if (this.entityId === entityId) {
			this.entityId = null;
			this.current = null;
			this.applyUpdate = null;
		}
	}
}

export const editorBridge = new EditorBridge();
