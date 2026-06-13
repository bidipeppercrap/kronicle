import { env } from "cloudflare:test";
import { strFromU8, unzipSync } from "fflate";
import { describe, expect, it } from "vitest";
import app from "../src/index";

async function req(path: string, init: RequestInit = {}): Promise<Response> {
  const headers = new Headers(init.headers);
  headers.set("Authorization", "Bearer test-token");
  if (typeof init.body === "string") headers.set("Content-Type", "application/json");
  return app.request(path, { ...init, headers }, env);
}

async function create(body: Record<string, unknown>) {
  const res = await req("/api/entities", { method: "POST", body: JSON.stringify(body) });
  expect(res.status).toBe(201);
  return res.json<Record<string, any>>();
}

/** Seed a small but representative vault: parent/child, a relationship, a
 *  revision, a media file, and an entity with tags. Returns key ids. */
async function seed() {
  const house = await create({ name: "House Vael", type: "faction" });
  const guli = await create({
    name: "Guli",
    type: "character",
    parent_id: house.id,
    content: "First draft.",
    metadata: { tags: ["protagonist", "orphan"], age: 22 },
  });
  const place = await create({ name: "Verdwijn", type: "location" });

  // A content edit snapshots the prior prose as a revision.
  await req(`/api/entities/${guli.id}`, {
    method: "PUT",
    body: JSON.stringify({ content: "Second draft about [[verdwijn]]." }),
  });

  await req("/api/relationships", {
    method: "POST",
    body: JSON.stringify({ source_id: guli.id, target_id: place.id, type: "resides_in" }),
  });

  const form = new FormData();
  form.append("file", new File(["fake-png-bytes"], "portrait.png", { type: "image/png" }));
  form.append("entity_id", guli.id);
  form.append("media_type", "portrait");
  const up = await req("/api/media", { method: "POST", body: form });
  expect(up.status).toBe(201);

  return { house, guli, place };
}

describe("export", () => {
  it("requires auth", async () => {
    expect((await app.request("/api/export", {}, env)).status).toBe(401);
  });

  it("produces a zip with the manifest, Markdown files, and media bytes", async () => {
    const { guli } = await seed();

    const res = await req("/api/export");
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toBe("application/zip");
    expect(res.headers.get("Content-Disposition")).toContain("kronicle-backup-");

    const zip = unzipSync(new Uint8Array(await res.arrayBuffer()));

    const manifest = JSON.parse(strFromU8(zip["kronicle.json"]));
    expect(manifest.version).toBe(1);
    expect(manifest.entities).toHaveLength(3);
    expect(manifest.relationships).toHaveLength(1);
    expect(manifest.revisions.length).toBeGreaterThanOrEqual(1);
    expect(manifest.media).toHaveLength(1);

    // One Markdown file per entity, nested by type, with YAML frontmatter.
    const md = strFromU8(zip["character/guli.md"]);
    expect(md).toContain("---");
    expect(md).toContain('slug: "guli"');
    expect(md).toContain('tags: ["protagonist","orphan"]');
    expect(md).toContain('parent: "house-vael"');
    expect(md).toContain("Second draft about [[verdwijn]].");

    // Media bytes ride along under their R2 key.
    const mediaKey = manifest.media[0].r2_key as string;
    expect(strFromU8(zip[mediaKey])).toBe("fake-png-bytes");
    expect(manifest.media[0].content_type).toBe("image/png");
    void guli;
  });

  it("never includes the AI provider key", async () => {
    await req("/api/settings/ai", {
      method: "PUT",
      body: JSON.stringify({ api_key: "sk-super-secret-1234" }),
    });
    const zip = unzipSync(new Uint8Array(await (await req("/api/export")).arrayBuffer()));
    const manifestText = strFromU8(zip["kronicle.json"]);
    expect(manifestText).not.toContain("sk-super-secret-1234");
    expect(JSON.parse(manifestText).settings).not.toHaveProperty("deepseek_api_key");
  });
});

describe("import", () => {
  it("refuses a non-empty vault without ?replace=true", async () => {
    await seed();
    const exportRes = await req("/api/export");
    const zip = new Uint8Array(await exportRes.arrayBuffer());

    const res = await req("/api/import", {
      method: "POST",
      body: zip,
      headers: { "Content-Type": "application/zip" },
    });
    expect(res.status).toBe(409);
  });

  it("round-trips the whole vault with ?replace=true", async () => {
    const { guli, house, place } = await seed();
    const zip = new Uint8Array(await (await req("/api/export")).arrayBuffer());

    const res = await req("/api/import?replace=true", {
      method: "POST",
      body: zip,
      headers: { "Content-Type": "application/zip" },
    });
    expect(res.status).toBe(200);
    const { imported } = await res.json<Record<string, any>>();
    expect(imported).toMatchObject({ entities: 3, relationships: 1, media: 1 });

    // Ids are preserved, so we can re-fetch by the original id.
    const restored = await req(`/api/entities/${guli.id}`).then((r) => r.json<Record<string, any>>());
    expect(restored.name).toBe("Guli");
    expect(restored.parent_id).toBe(house.id);
    expect(restored.content).toContain("Second draft");
    expect(restored.metadata.tags).toEqual(["protagonist", "orphan"]);
    expect(restored.relationships).toHaveLength(1);
    expect(restored.relationships[0].target_id).toBe(place.id);
    expect(restored.media).toHaveLength(1);

    // The media blob is back in R2 and streamable.
    const file = await req(`/api/media/${restored.media[0].id}/file`);
    expect(file.status).toBe(200);
    expect(await file.text()).toBe("fake-png-bytes");
  });

  it("rejects a body that is not a kronicle zip", async () => {
    const res = await req("/api/import?replace=true", {
      method: "POST",
      body: new Uint8Array([1, 2, 3, 4]),
      headers: { "Content-Type": "application/zip" },
    });
    expect(res.status).toBe(400);
  });
});
