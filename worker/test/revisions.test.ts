import { env } from "cloudflare:test";
import { desc, eq } from "drizzle-orm";
import { drizzle } from "drizzle-orm/d1";
import { describe, expect, it } from "vitest";
import { entityRevisions } from "../src/db/schema";
import app from "../src/index";

async function req(path: string, init: RequestInit = {}): Promise<Response> {
  const headers = new Headers(init.headers);
  headers.set("Authorization", "Bearer test-token");
  if (typeof init.body === "string") {
    headers.set("Content-Type", "application/json");
  }
  return app.request(path, { ...init, headers }, env);
}

async function create(body: Record<string, unknown>) {
  const res = await req("/api/entities", {
    method: "POST",
    body: JSON.stringify(body),
  });
  expect(res.status).toBe(201);
  return res.json<Record<string, any>>();
}

async function update(id: string, body: Record<string, unknown>) {
  const res = await req(`/api/entities/${id}`, {
    method: "PUT",
    body: JSON.stringify(body),
  });
  expect(res.status).toBe(200);
  return res.json<Record<string, any>>();
}

async function listRevisions(id: string) {
  const res = await req(`/api/entities/${id}/revisions`);
  expect(res.status).toBe(200);
  const body = await res.json<{ items: Record<string, any>[] }>();
  return body.items;
}

/** Backdate the newest revision so the next save falls outside the
 * 10-minute coalescing window. */
async function ageNewestRevision(entityId: string, minutes: number) {
  const db = drizzle(env.DB);
  const newest = await db
    .select({ id: entityRevisions.id })
    .from(entityRevisions)
    .where(eq(entityRevisions.entity_id, entityId))
    .orderBy(desc(entityRevisions.created_at))
    .limit(1)
    .get();
  if (!newest) return;
  const aged = new Date(Date.now() - minutes * 60_000).toISOString();
  await db
    .update(entityRevisions)
    .set({ created_at: aged })
    .where(eq(entityRevisions.id, newest.id))
    .run();
}

describe("revision snapshots", () => {
  it("snapshots the prior content on a content-changing save", async () => {
    const e = await create({ name: "Guli", content: "v1" });
    await update(e.id, { content: "v2" });

    const items = await listRevisions(e.id);
    expect(items).toHaveLength(1);
    expect(items[0].content).toBe("v1");
    expect(items[0].entity_id).toBe(e.id);
  });

  it("does not snapshot when content is absent or unchanged", async () => {
    const e = await create({ name: "Guli", content: "v1" });
    await update(e.id, { summary: "new summary" });
    await update(e.id, { content: "v1" });

    expect(await listRevisions(e.id)).toHaveLength(0);
  });

  it("coalesces saves inside the 10-minute window", async () => {
    const e = await create({ name: "Guli", content: "v1" });
    await update(e.id, { content: "v2" });
    await update(e.id, { content: "v3" });

    const items = await listRevisions(e.id);
    expect(items).toHaveLength(1);
    expect(items[0].content).toBe("v1");
  });

  it("snapshots again once the window has passed", async () => {
    const e = await create({ name: "Guli", content: "v1" });
    await update(e.id, { content: "v2" });
    await ageNewestRevision(e.id, 11);
    await update(e.id, { content: "v3" });

    const items = await listRevisions(e.id);
    expect(items).toHaveLength(2);
    expect(items[0].content).toBe("v2"); // newest first
    expect(items[1].content).toBe("v1");
  });

  it("keeps only the newest 20 revisions", async () => {
    const e = await create({ name: "Guli", content: "v0" });
    for (let i = 1; i <= 22; i++) {
      await update(e.id, { content: `v${i}` });
      await ageNewestRevision(e.id, 11);
    }

    const items = await listRevisions(e.id);
    expect(items).toHaveLength(20);
    // v0 and v1 (the two oldest snapshots) were pruned.
    expect(items.at(-1)?.content).toBe("v2");
    expect(items[0].content).toBe("v21");
  });
});

describe("revision restore", () => {
  it("restores old content and snapshots the current content first", async () => {
    const e = await create({ name: "Guli", content: "v1" });
    await update(e.id, { content: "v2" });
    const [rev] = await listRevisions(e.id); // holds v1

    const res = await req(`/api/entities/${e.id}/revisions/${rev.id}/restore`, {
      method: "POST",
    });
    expect(res.status).toBe(200);
    const restored = await res.json<Record<string, any>>();
    expect(restored.content).toBe("v1");

    const fetched = await req(`/api/entities/${e.id}`).then((r) => r.json<any>());
    expect(fetched.content).toBe("v1");

    // The pre-restore content (v2) was snapshotted despite the window.
    const items = await listRevisions(e.id);
    expect(items[0].content).toBe("v2");
  });

  it("404s for a revision belonging to another entity", async () => {
    const a = await create({ name: "A", content: "a1" });
    const b = await create({ name: "B", content: "b1" });
    await update(a.id, { content: "a2" });
    const [rev] = await listRevisions(a.id);

    const res = await req(`/api/entities/${b.id}/revisions/${rev.id}/restore`, {
      method: "POST",
    });
    expect(res.status).toBe(404);
  });

  it("deleting an entity removes its revisions", async () => {
    const e = await create({ name: "Guli", content: "v1" });
    await update(e.id, { content: "v2" });

    const del = await req(`/api/entities/${e.id}`, { method: "DELETE" });
    expect(del.status).toBe(204);

    const db = drizzle(env.DB);
    const rows = await db
      .select()
      .from(entityRevisions)
      .where(eq(entityRevisions.entity_id, e.id))
      .all();
    expect(rows).toHaveLength(0);
  });
});
