import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import app from "../src/index";

async function req(
  path: string,
  init: RequestInit = {}
): Promise<Response> {
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

describe("auth", () => {
  it("rejects requests without a token", async () => {
    const res = await app.request("/api/entities", {}, env);
    expect(res.status).toBe(401);
  });

  it("rejects a wrong token", async () => {
    const res = await app.request(
      "/api/entities",
      { headers: { Authorization: "Bearer wrong" } },
      env
    );
    expect(res.status).toBe(401);
  });
});

describe("quick capture & slugs", () => {
  it("creates a stub from just a name", async () => {
    const e = await create({ name: "Guli" });
    expect(e.status).toBe("stub");
    expect(e.type).toBe("lore");
    expect(e.slug).toBe("guli");
    expect(e.id).toBeTruthy();
  });

  it("suffixes generated slugs on collision", async () => {
    const first = await create({ name: "Guli" });
    const second = await create({ name: "Guli" });
    expect(first.slug).toBe("guli");
    expect(second.slug).toBe("guli-2");
  });

  it("rejects an explicit slug that is taken", async () => {
    await create({ name: "Guli", slug: "guli" });
    const res = await req("/api/entities", {
      method: "POST",
      body: JSON.stringify({ name: "Other Guli", slug: "guli" }),
    });
    expect(res.status).toBe(409);
  });
});

describe("entities CRUD", () => {
  it("round-trips a full create and fetches by slug", async () => {
    const created = await create({
      name: "Guli",
      type: "character",
      status: "draft",
      summary: "A palm-fire wielder",
      content: "Guli grew up in [[bangsur-town]].",
      metadata: { gender: "male", species: "human", age: 22 },
    });
    const res = await req(`/api/entities/${created.slug}`);
    expect(res.status).toBe(200);
    const fetched = await res.json<Record<string, any>>();
    expect(fetched.id).toBe(created.id);
    expect(fetched.metadata).toEqual({
      gender: "male",
      species: "human",
      age: 22,
    });
    expect(fetched.relationships).toEqual([]);
    expect(fetched.media).toEqual([]);
  });

  it("updates partially — untouched fields survive", async () => {
    const e = await create({ name: "Guli", type: "character", summary: "old" });
    const res = await req(`/api/entities/${e.id}`, {
      method: "PUT",
      body: JSON.stringify({ summary: "new summary", status: "canon" }),
    });
    expect(res.status).toBe(200);
    const updated = await res.json<Record<string, any>>();
    expect(updated.summary).toBe("new summary");
    expect(updated.status).toBe("canon");
    expect(updated.name).toBe("Guli");
    expect(updated.type).toBe("character");
  });

  it("lists with filters and a total", async () => {
    await create({ name: "Guli", type: "character", status: "canon" });
    await create({ name: "Mira", type: "character" });
    await create({ name: "Bangsur Town", type: "location" });
    const res = await req("/api/entities?type=character");
    const body = await res.json<Record<string, any>>();
    expect(body.total).toBe(2);
    expect(body.items).toHaveLength(2);
    expect(body.limit).toBe(50);

    const canon = await req("/api/entities?type=character&status=canon").then(
      (r) => r.json<Record<string, any>>()
    );
    expect(canon.total).toBe(1);
    expect(canon.items[0].name).toBe("Guli");
  });

  it("blocks deleting an entity with children", async () => {
    const story = await create({ name: "The Awakening", type: "story" });
    const chapter = await create({
      name: "Chapter One",
      type: "chapter",
      parent_id: story.id,
    });

    const blocked = await req(`/api/entities/${story.id}`, {
      method: "DELETE",
    });
    expect(blocked.status).toBe(409);

    expect(
      (await req(`/api/entities/${chapter.id}`, { method: "DELETE" })).status
    ).toBe(204);
    expect(
      (await req(`/api/entities/${story.id}`, { method: "DELETE" })).status
    ).toBe(204);
    expect((await req(`/api/entities/${story.id}`)).status).toBe(404);
  });
});

describe("slug rename", () => {
  it("rewrites wikilinks across all content atomically", async () => {
    const town = await create({ name: "Bangsur Town", type: "location" });
    const guli = await create({
      name: "Guli",
      type: "character",
      content:
        "Guli grew up in [[bangsur-town]] — see [[bangsur-town|the town]]. Not [[bangsur-township]].",
    });

    const res = await req(`/api/entities/${town.id}`, {
      method: "PUT",
      body: JSON.stringify({ slug: "bangsur" }),
    });
    expect(res.status).toBe(200);

    const fetched = await req(`/api/entities/${guli.id}`).then((r) =>
      r.json<Record<string, any>>()
    );
    expect(fetched.content).toBe(
      "Guli grew up in [[bangsur]] — see [[bangsur|the town]]. Not [[bangsur-township]]."
    );

    expect((await req("/api/entities/bangsur")).status).toBe(200);
    expect((await req("/api/entities/bangsur-town")).status).toBe(404);
  });
});

describe("era validation", () => {
  it("rejects an unknown era and accepts a real one", async () => {
    const bad = await req("/api/entities", {
      method: "POST",
      body: JSON.stringify({
        name: "The Great Fire",
        type: "event",
        metadata: { era: "age-of-nothing" },
      }),
    });
    expect(bad.status).toBe(422);

    await create({
      name: "Age of Conflict",
      type: "lore",
      metadata: { category: "era" },
    });
    const good = await create({
      name: "The Great Fire",
      type: "event",
      metadata: { era: "age-of-conflict", order_index: 100 },
    });
    expect(good.metadata.era).toBe("age-of-conflict");
  });

  it("validates era on update too", async () => {
    const event = await create({ name: "The Great Fire", type: "event" });
    const res = await req(`/api/entities/${event.id}`, {
      method: "PUT",
      body: JSON.stringify({ metadata: { era: "typo-era" } }),
    });
    expect(res.status).toBe(422);
  });
});

describe("timeline", () => {
  it("returns events in chronological order and the era entities", async () => {
    await create({ name: "Saga Era", type: "lore", metadata: { category: "era" } });
    const third = await create({
      name: "Third Event",
      type: "event",
      status: "canon",
      metadata: { era: "saga-era", order_index: 300 },
    });
    const first = await create({
      name: "First Event",
      type: "event",
      status: "canon",
      metadata: { era: "saga-era", order_index: 100 },
    });
    const second = await create({
      name: "Second Event",
      type: "event",
      status: "canon",
      metadata: { era: "saga-era", order_index: 200 },
    });

    const res = await req("/api/timeline?era=saga-era&status=canon");
    expect(res.status).toBe(200);
    const body = await res.json<{ items: any[]; eras: any[] }>();
    expect(body.items.map((e) => e.id)).toEqual([first.id, second.id, third.id]);
    expect(body.eras.some((e) => e.slug === "saga-era")).toBe(true);
  });

  it("includes era-less events and sorts the position-less last", async () => {
    await create({ name: "Dawn Era", type: "lore", metadata: { category: "era" } });
    const dated = await create({
      name: "Dated Dawn Event",
      type: "event",
      status: "canon",
      metadata: { era: "dawn-era", order_index: 50 },
    });
    const undated = await create({
      name: "Undated Dawn Event",
      type: "event",
      status: "canon",
      metadata: { era: "dawn-era" },
    });

    const res = await req("/api/timeline?era=dawn-era");
    const body = await res.json<{ items: any[] }>();
    expect(body.items.map((e) => e.id)).toEqual([dated.id, undated.id]);
  });

  it("filters by status and excludes non-events tagged with the era", async () => {
    await create({ name: "Mist Era", type: "lore", metadata: { category: "era" } });
    await create({
      name: "Canon Mist Event",
      type: "event",
      status: "canon",
      metadata: { era: "mist-era", order_index: 10 },
    });
    await create({
      name: "Draft Mist Event",
      type: "event",
      status: "draft",
      metadata: { era: "mist-era", order_index: 20 },
    });
    // A lore entry can carry an era too, but the timeline is events only.
    await create({
      name: "Mist Lore",
      type: "lore",
      status: "canon",
      metadata: { era: "mist-era" },
    });

    const canonOnly = await req("/api/timeline?era=mist-era&status=canon");
    const canonBody = await canonOnly.json<{ items: any[] }>();
    expect(canonBody.items.map((e) => e.name)).toEqual(["Canon Mist Event"]);

    const all = await req("/api/timeline?era=mist-era");
    const allBody = await all.json<{ items: any[] }>();
    expect(allBody.items.map((e) => e.name)).toEqual([
      "Canon Mist Event",
      "Draft Mist Event",
    ]);
  });
});

describe("relationships", () => {
  it("creates, reads from both directions, rejects duplicates, deletes", async () => {
    const guli = await create({ name: "Guli", type: "character" });
    const town = await create({ name: "Bangsur Town", type: "location" });

    const res = await req("/api/relationships", {
      method: "POST",
      body: JSON.stringify({
        source_id: guli.id,
        target_id: town.slug,
        type: "born_in",
        label: "birthplace",
      }),
    });
    expect(res.status).toBe(201);
    const rel = await res.json<Record<string, any>>();
    expect(rel.target_id).toBe(town.id);

    const dup = await req("/api/relationships", {
      method: "POST",
      body: JSON.stringify({
        source_id: guli.id,
        target_id: town.id,
        type: "born_in",
      }),
    });
    expect(dup.status).toBe(409);

    const fromTarget = await req(
      `/api/entities/${town.id}/relationships`
    ).then((r) => r.json<Record<string, any>[]>());
    expect(fromTarget).toHaveLength(1);
    expect(fromTarget[0].source_id).toBe(guli.id);

    expect(
      (await req(`/api/relationships/${rel.id}`, { method: "DELETE" })).status
    ).toBe(204);
    const after = await req(`/api/entities/${guli.id}/relationships`).then(
      (r) => r.json<Record<string, any>[]>()
    );
    expect(after).toHaveLength(0);
  });

  it("deleting an entity removes its relationships", async () => {
    const guli = await create({ name: "Guli", type: "character" });
    const mira = await create({ name: "Mira", type: "character" });
    await req("/api/relationships", {
      method: "POST",
      body: JSON.stringify({
        source_id: guli.id,
        target_id: mira.id,
        type: "friend_of",
      }),
    });

    expect(
      (await req(`/api/entities/${mira.id}`, { method: "DELETE" })).status
    ).toBe(204);
    const rels = await req(`/api/entities/${guli.id}/relationships`).then(
      (r) => r.json<Record<string, any>[]>()
    );
    expect(rels).toHaveLength(0);
  });
});

describe("backlinks", () => {
  it("finds entities mentioning [[slug]] and [[slug|alias]]", async () => {
    const town = await create({ name: "Bangsur Town", type: "location" });
    const guli = await create({
      name: "Guli",
      type: "character",
      content: "Born in [[bangsur-town]].",
    });
    const mira = await create({
      name: "Mira",
      type: "character",
      content: "Visited [[bangsur-town|the town]] once.",
    });
    await create({ name: "Unrelated", type: "lore", content: "Nothing here." });

    const backlinks = await req(`/api/entities/${town.id}/backlinks`).then(
      (r) => r.json<Record<string, any>[]>()
    );
    const slugs = backlinks.map((b) => b.slug).sort();
    expect(slugs).toEqual([guli.slug, mira.slug].sort());
  });
});

describe("search", () => {
  it("matches name, summary, and content with LIKE", async () => {
    await create({
      name: "Guli",
      type: "character",
      content: "Wields palm-fire.",
    });
    await create({
      name: "Mira",
      type: "character",
      summary: "Guli's rival",
    });
    await create({ name: "Bangsur Town", type: "location" });

    const res = await req("/api/search?q=guli");
    const body = await res.json<Record<string, any>>();
    expect(body.total).toBe(2);

    const typed = await req("/api/search?q=guli&type=location").then((r) =>
      r.json<Record<string, any>>()
    );
    expect(typed.total).toBe(0);

    expect((await req("/api/search")).status).toBe(400);
  });
});

describe("media", () => {
  it("uploads, streams, and deletes a file", async () => {
    const guli = await create({ name: "Guli", type: "character" });

    const form = new FormData();
    form.append(
      "file",
      new File(["fake-png-bytes"], "portrait.png", { type: "image/png" })
    );
    form.append("entity_id", guli.id);
    form.append("media_type", "portrait");
    form.append("alt_text", "Guli's portrait");

    const uploaded = await req("/api/media", { method: "POST", body: form });
    expect(uploaded.status).toBe(201);
    const row = await uploaded.json<Record<string, any>>();
    expect(row.r2_key).toContain("portrait.png");

    const file = await req(`/api/media/${row.id}/file`);
    expect(file.status).toBe(200);
    expect(file.headers.get("Content-Type")).toBe("image/png");
    expect(await file.text()).toBe("fake-png-bytes");

    const listed = await req(`/api/entities/${guli.id}/media`).then((r) =>
      r.json<Record<string, any>[]>()
    );
    expect(listed).toHaveLength(1);

    expect(
      (await req(`/api/media/${row.id}`, { method: "DELETE" })).status
    ).toBe(204);
    expect((await req(`/api/media/${row.id}/file`)).status).toBe(404);
  });

  it("rejects uploads for a missing entity or bad media_type", async () => {
    const form = new FormData();
    form.append("file", new File(["x"], "x.png", { type: "image/png" }));
    form.append("entity_id", "nope");
    form.append("media_type", "portrait");
    expect((await req("/api/media", { method: "POST", body: form })).status).toBe(404);

    const guli = await create({ name: "Guli", type: "character" });
    const bad = new FormData();
    bad.append("file", new File(["x"], "x.png", { type: "image/png" }));
    bad.append("entity_id", guli.id);
    bad.append("media_type", "selfie");
    expect((await req("/api/media", { method: "POST", body: bad })).status).toBe(400);
  });
});
