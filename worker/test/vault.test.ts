import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
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

describe("tags", () => {
  it("trims, dedupes, round-trips, and filters by ?tag=", async () => {
    const guli = await create({
      name: "Guli",
      type: "character",
      metadata: { tags: ["villain", "villain", " book-2 "], age: 22 },
    });
    expect(guli.metadata.tags).toEqual(["villain", "book-2"]);
    expect(guli.metadata.age).toBe(22);

    await create({ name: "Mira", type: "character" });
    // A matching value elsewhere in metadata must not match the tag filter.
    await create({
      name: "Bangsur Town",
      type: "location",
      metadata: { category: "villain" },
    });

    const tagged = await req("/api/entities?tag=villain").then((r) =>
      r.json<Record<string, any>>()
    );
    expect(tagged.total).toBe(1);
    expect(tagged.items[0].name).toBe("Guli");

    const none = await req("/api/entities?tag=hero").then((r) =>
      r.json<Record<string, any>>()
    );
    expect(none.total).toBe(0);
  });

  it("survives a partial update and rejects malformed tags", async () => {
    const e = await create({
      name: "Guli",
      metadata: { tags: ["villain"] },
    });
    const updated = await req(`/api/entities/${e.id}`, {
      method: "PUT",
      body: JSON.stringify({ metadata: { tags: ["villain", "book-2"] } }),
    });
    expect(updated.status).toBe(200);
    expect((await updated.json<Record<string, any>>()).metadata.tags).toEqual([
      "villain",
      "book-2",
    ]);

    for (const tags of ["villain", [""], [1], [{ tag: "x" }]]) {
      const bad = await req("/api/entities", {
        method: "POST",
        body: JSON.stringify({ name: "Bad", metadata: { tags } }),
      });
      expect(bad.status).toBe(400);
    }
  });
});

describe("family relationships", () => {
  it("accepts the family verbs and still rejects unknown types", async () => {
    const guli = await create({ name: "Guli", type: "character" });
    const mira = await create({ name: "Mira", type: "character" });

    for (const type of ["parent_of", "sibling_of", "married_to"]) {
      const res = await req("/api/relationships", {
        method: "POST",
        body: JSON.stringify({
          source_id: guli.id,
          target_id: mira.id,
          type,
        }),
      });
      expect(res.status).toBe(201);
    }

    const bad = await req("/api/relationships", {
      method: "POST",
      body: JSON.stringify({
        source_id: guli.id,
        target_id: mira.id,
        type: "step_uncle_of",
      }),
    });
    expect(bad.status).toBe(400);
  });
});

describe("diagnostics", () => {
  it("reports broken wikilinks, orphans, and stale stubs", async () => {
    const town = await create({ name: "Bangsur Town", type: "location" });
    const guli = await create({
      name: "Guli",
      type: "character",
      content:
        "Born in [[bangsur-town]]. Trained at [[no-such-place]] — see [[no-such-place|the ruins]].",
    });
    // Orphan: nothing points at it, it points at nothing.
    const orphan = await create({ name: "Forgotten Blade", type: "lore" });
    // Connected via relationship — not an orphan.
    const mira = await create({ name: "Mira", type: "character" });
    await req("/api/relationships", {
      method: "POST",
      body: JSON.stringify({
        source_id: mira.id,
        target_id: town.id,
        type: "resides_in",
      }),
    });
    // A stub past the 14-day triage window (backdated directly — the API
    // always stamps now()).
    const stale = await create({ name: "Dusty Idea" });
    const old = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    await env.DB.prepare(
      "UPDATE entities SET updated_at = ?, created_at = ? WHERE id = ?"
    )
      .bind(old, old, stale.id)
      .run();
    // A fresh stub stays off the report.
    await create({ name: "Fresh Idea" });

    const report = await req("/api/diagnostics").then((r) =>
      r.json<Record<string, any>>()
    );

    expect(report.broken_links).toHaveLength(1);
    expect(report.broken_links[0].missing_slug).toBe("no-such-place");
    expect(report.broken_links[0].count).toBe(2);
    expect(report.broken_links[0].slug).toBe(guli.slug);

    const orphanSlugs = report.orphans.map((o: any) => o.slug);
    expect(orphanSlugs).toContain(orphan.slug);
    expect(orphanSlugs).not.toContain(town.slug); // mentioned + related
    expect(orphanSlugs).not.toContain(guli.slug); // links out
    expect(orphanSlugs).not.toContain(mira.slug); // has a relationship

    expect(report.stale_stubs).toHaveLength(1);
    expect(report.stale_stubs[0].name).toBe("Dusty Idea");
  });

  it("returns empty arrays for a healthy vault", async () => {
    await create({ name: "Bangsur Town", type: "location" });
    await create({
      name: "Guli",
      type: "character",
      status: "canon",
      content: "Born in [[bangsur-town]].",
    });

    const report = await req("/api/diagnostics").then((r) =>
      r.json<Record<string, any>>()
    );
    expect(report.broken_links).toEqual([]);
    expect(report.orphans).toEqual([]);
    // Both fresh: the stub-aged check has nothing to flag.
    expect(report.stale_stubs).toEqual([]);
  });
});
