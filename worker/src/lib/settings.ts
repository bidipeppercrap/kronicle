import { eq, inArray } from "drizzle-orm";
import type { DrizzleD1Database } from "drizzle-orm/d1";
import { settings } from "../db/schema";
import type { Bindings } from "../types";

/** Setting keys for the AI provider. DB values win; env vars are fallbacks. */
export const AI_SETTING_KEYS = {
  apiKey: "deepseek_api_key",
  apiUrl: "deepseek_api_url",
  model: "deepseek_model",
} as const;

export interface AiConfig {
  apiKey: string | null;
  /** Where the key came from, for the settings UI. */
  apiKeySource: "settings" | "env" | null;
  baseUrl: string | undefined;
  model: string | undefined;
}

export async function getAiConfig(
  db: DrizzleD1Database,
  env: Bindings
): Promise<AiConfig> {
  const rows = await db
    .select()
    .from(settings)
    .where(inArray(settings.key, Object.values(AI_SETTING_KEYS)))
    .all();
  const byKey = new Map(rows.map((r) => [r.key, r.value]));

  const dbKey = byKey.get(AI_SETTING_KEYS.apiKey);
  return {
    apiKey: dbKey ?? env.DEEPSEEK_API_KEY ?? null,
    apiKeySource: dbKey ? "settings" : env.DEEPSEEK_API_KEY ? "env" : null,
    baseUrl: byKey.get(AI_SETTING_KEYS.apiUrl) ?? env.DEEPSEEK_API_URL,
    model: byKey.get(AI_SETTING_KEYS.model) ?? env.DEEPSEEK_MODEL,
  };
}

/** Upsert when value is non-empty; delete the row (back to env fallback) when empty. */
export async function putSetting(
  db: DrizzleD1Database,
  key: string,
  value: string
): Promise<void> {
  if (!value) {
    await db.delete(settings).where(eq(settings.key, key));
    return;
  }
  await db
    .insert(settings)
    .values({ key, value, updated_at: new Date().toISOString() })
    .onConflictDoUpdate({
      target: settings.key,
      set: { value, updated_at: new Date().toISOString() },
    });
}
