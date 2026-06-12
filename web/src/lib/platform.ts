import { browser } from '$app/environment';

/** True on macOS/iOS, where the primary modifier key is ⌘. False during SSR. */
export const isMac = browser && /Mac|iPhone|iPad|iPod/i.test(navigator.platform);

/** Display label for the platform's primary modifier key, e.g. `${modKey}K`. */
export const modKey = isMac ? '⌘' : 'Ctrl+';
