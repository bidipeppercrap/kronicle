import { env } from '$env/dynamic/private';
import { error } from '@sveltejs/kit';

/**
 * Server-side client for the Kronicle Worker API. The bearer token lives
 * here and only here — it must never reach the browser (DESIGN.md, Auth).
 */

function config() {
	const base = env.API_URL ?? 'http://localhost:8787';
	const token = env.API_TOKEN;
	if (!token) throw error(500, 'API_TOKEN is not configured');
	return { base: base.replace(/\/$/, ''), token };
}

export async function apiFetch(
	fetcher: typeof fetch,
	path: string,
	init: RequestInit = {}
): Promise<Response> {
	const { base, token } = config();
	const headers = new Headers(init.headers);
	headers.set('Authorization', `Bearer ${token}`);
	return fetcher(`${base}/api${path}`, { ...init, headers });
}

/** GET helper that unwraps JSON and converts API failures into SvelteKit errors. */
export async function apiGet<T>(fetcher: typeof fetch, path: string): Promise<T> {
	const res = await apiFetch(fetcher, path);
	if (!res.ok) {
		const body = (await res.json().catch(() => null)) as { error?: string } | null;
		throw error(res.status === 404 ? 404 : 502, body?.error ?? `API request failed (${res.status})`);
	}
	return res.json() as Promise<T>;
}

export async function apiSend<T>(
	fetcher: typeof fetch,
	method: 'POST' | 'PUT' | 'DELETE',
	path: string,
	body?: unknown
): Promise<{ ok: boolean; status: number; data: T | null; message: string | null }> {
	const res = await apiFetch(fetcher, path, {
		method,
		headers: body !== undefined ? { 'Content-Type': 'application/json' } : undefined,
		body: body !== undefined ? JSON.stringify(body) : undefined
	});
	if (res.status === 204) return { ok: true, status: 204, data: null, message: null };
	const data = (await res.json().catch(() => null)) as T | null;
	const message =
		!res.ok && data && typeof data === 'object' && 'error' in data
			? String((data as { error: unknown }).error)
			: null;
	return { ok: res.ok, status: res.status, data: res.ok ? data : null, message };
}
