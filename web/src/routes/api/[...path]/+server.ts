import { apiFetch } from '$lib/server/api';
import type { RequestHandler } from './$types';

/**
 * Pass-through proxy for client-side calls (autosave, palette search,
 * quick capture). Attaches the bearer token server-side; the browser
 * never sees it. Cloudflare Access guards who can reach this proxy.
 */
const proxy: RequestHandler = async ({ params, url, request, fetch }) => {
	const target = `/${params.path}${url.search}`;
	const hasBody = request.method !== 'GET' && request.method !== 'HEAD';
	// Forward the body as raw bytes with its original Content-Type —
	// multipart uploads (media) carry a boundary and binary payloads.
	const contentType = request.headers.get('Content-Type');
	const res = await apiFetch(fetch, target, {
		method: request.method,
		headers: hasBody && contentType ? { 'Content-Type': contentType } : undefined,
		body: hasBody ? await request.arrayBuffer() : undefined
	});
	return new Response(res.body, {
		status: res.status,
		headers: { 'Content-Type': res.headers.get('Content-Type') ?? 'application/json' }
	});
};

export const GET = proxy;
export const POST = proxy;
export const PUT = proxy;
export const DELETE = proxy;
