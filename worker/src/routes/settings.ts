import { drizzle } from "drizzle-orm/d1";
import type { DrizzleD1Database } from "drizzle-orm/d1";
import { Hono } from "hono";
import { z } from "zod";
import { AI_SETTING_KEYS, getAiConfig, putSetting } from "../lib/settings";
import { parseJson } from "../lib/validate";
import type { Bindings } from "../types";

const app = new Hono<{ Bindings: Bindings }>();

/**
 * AI provider settings, editable from the web UI. The key is stored in D1
 * (the Worker env secret stays as a fallback) and is never echoed back —
 * responses carry only a masked hint.
 */

const putSchema = z.object({
  api_key: z.string().trim().optional(),
  api_url: z.string().trim().optional(),
  model: z.string().trim().optional(),
});

function hint(key: string | null): string | null {
  if (!key) return null;
  return key.length <= 4 ? "…" : `…${key.slice(-4)}`;
}

async function aiSettingsBody(db: DrizzleD1Database, env: Bindings) {
  const cfg = await getAiConfig(db, env);
  return {
    api_key_set: cfg.apiKey !== null,
    api_key_hint: hint(cfg.apiKey),
    api_key_source: cfg.apiKeySource,
    api_url: cfg.baseUrl ?? null,
    model: cfg.model ?? null,
  };
}

app.get("/settings/ai", async (c) => {
  const db = drizzle(c.env.DB);
  return c.json(await aiSettingsBody(db, c.env));
});

// Partial update: only provided fields change; empty string clears back to env.
app.put("/settings/ai", async (c) => {
  const body = await parseJson(c, putSchema);
  const db = drizzle(c.env.DB);
  if (body.api_key !== undefined)
    await putSetting(db, AI_SETTING_KEYS.apiKey, body.api_key);
  if (body.api_url !== undefined)
    await putSetting(db, AI_SETTING_KEYS.apiUrl, body.api_url);
  if (body.model !== undefined)
    await putSetting(db, AI_SETTING_KEYS.model, body.model);
  return c.json(await aiSettingsBody(db, c.env));
});

export default app;
