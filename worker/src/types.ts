export type Bindings = {
  DB: D1Database;
  MEDIA: R2Bucket;
  API_TOKEN: string;
  DEEPSEEK_API_KEY: string;
  /** Override the DeepSeek endpoint (tests point this at a mock). */
  DEEPSEEK_API_URL?: string;
  /** Defaults to "deepseek-chat". */
  DEEPSEEK_MODEL?: string;
};
