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

function putAi(body: Record<string, unknown>) {
  return req("/api/settings/ai", { method: "PUT", body: JSON.stringify(body) });
}

describe("ai settings", () => {
  it("requires auth", async () => {
    const res = await app.request("/api/settings/ai", {}, env);
    expect(res.status).toBe(401);
  });

  it("falls back to the env key when nothing is saved", async () => {
    const res = await req("/api/settings/ai");
    expect(res.status).toBe(200);
    const body = await res.json<Record<string, any>>();
    expect(body.api_key_set).toBe(true);
    expect(body.api_key_source).toBe("env");
    // env key is "test-deepseek-key"
    expect(body.api_key_hint).toBe("…-key");
  });

  it("saves a key and returns only a masked hint, never the key", async () => {
    const res = await putAi({ api_key: "sk-secret-9876" });
    expect(res.status).toBe(200);
    const text = await res.text();
    expect(text).not.toContain("sk-secret-9876");
    const body = JSON.parse(text);
    expect(body.api_key_set).toBe(true);
    expect(body.api_key_source).toBe("settings");
    expect(body.api_key_hint).toBe("…9876");

    const get = await req("/api/settings/ai");
    expect(await get.text()).not.toContain("sk-secret-9876");
  });

  it("updates fields independently", async () => {
    await putAi({ api_key: "sk-secret-9876" });
    const res = await putAi({ model: "deepseek-reasoner" });
    const body = await res.json<Record<string, any>>();
    expect(body.model).toBe("deepseek-reasoner");
    expect(body.api_key_source).toBe("settings");
  });

  it("clearing the key falls back to env", async () => {
    await putAi({ api_key: "sk-secret-9876" });
    const res = await putAi({ api_key: "" });
    const body = await res.json<Record<string, any>>();
    expect(body.api_key_source).toBe("env");
    expect(body.api_key_hint).toBe("…-key");
  });
});
