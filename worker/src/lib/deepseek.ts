/**
 * Minimal streaming client for DeepSeek's OpenAI-compatible
 * chat-completions API. Text deltas are surfaced through a callback as
 * they arrive; tool-call deltas are accumulated and returned whole.
 */

export interface ToolCall {
  id: string;
  type: "function";
  function: { name: string; arguments: string };
}

export interface ChatMessage {
  role: "system" | "user" | "assistant" | "tool";
  content: string | null;
  tool_calls?: ToolCall[];
  tool_call_id?: string;
}

export interface ToolDefinition {
  type: "function";
  function: {
    name: string;
    description: string;
    parameters: Record<string, unknown>;
  };
}

interface StreamDelta {
  content?: string | null;
  tool_calls?: {
    index: number;
    id?: string;
    function?: { name?: string; arguments?: string };
  }[];
}

export interface CompletionResult {
  content: string;
  toolCalls: ToolCall[];
}

export async function streamCompletion(opts: {
  apiKey: string;
  baseUrl?: string;
  model?: string;
  messages: ChatMessage[];
  tools: ToolDefinition[];
  onText: (delta: string) => Promise<void>;
}): Promise<CompletionResult> {
  const base = (opts.baseUrl ?? "https://api.deepseek.com").replace(/\/$/, "");
  const res = await fetch(`${base}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${opts.apiKey}`,
    },
    body: JSON.stringify({
      model: opts.model ?? "deepseek-chat",
      messages: opts.messages,
      tools: opts.tools,
      stream: true,
    }),
  });
  if (!res.ok || !res.body) {
    const detail = await res.text().catch(() => "");
    throw new Error(
      `DeepSeek request failed (${res.status}) ${detail.slice(0, 200)}`
    );
  }

  let content = "";
  const calls = new Map<number, ToolCall>();

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    let nl: number;
    while ((nl = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, nl).trim();
      buffer = buffer.slice(nl + 1);
      if (!line.startsWith("data:")) continue;
      const payload = line.slice(5).trim();
      if (payload === "[DONE]") continue;
      let delta: StreamDelta | undefined;
      try {
        delta = JSON.parse(payload).choices?.[0]?.delta;
      } catch {
        continue; // partial keep-alive noise — never worth failing the turn
      }
      if (!delta) continue;
      if (delta.content) {
        content += delta.content;
        await opts.onText(delta.content);
      }
      for (const tc of delta.tool_calls ?? []) {
        let call = calls.get(tc.index);
        if (!call) {
          call = { id: "", type: "function", function: { name: "", arguments: "" } };
          calls.set(tc.index, call);
        }
        if (tc.id) call.id = tc.id;
        if (tc.function?.name) call.function.name = tc.function.name;
        if (tc.function?.arguments) call.function.arguments += tc.function.arguments;
      }
    }
  }

  return { content, toolCalls: [...calls.values()].filter((c) => c.function.name) };
}
