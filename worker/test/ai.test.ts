import { env, fetchMock } from "cloudflare:test";
import { afterEach, beforeAll, describe, expect, it } from "vitest";
import app from "../src/index";

beforeAll(() => {
  fetchMock.activate();
  fetchMock.disableNetConnect();
});
afterEach(() => fetchMock.assertNoPendingInterceptors());

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

function chat(entityId: string, content = "Hi") {
  return req("/api/ai/chat", {
    method: "POST",
    body: JSON.stringify({
      entity_id: entityId,
      messages: [{ role: "user", content }],
    }),
  });
}

/** DeepSeek-shaped SSE body from a list of delta chunks. */
function completion(...deltas: Record<string, unknown>[]): string {
  const lines = deltas.map(
    (delta) => `data: ${JSON.stringify({ choices: [{ delta }] })}\n`
  );
  return `${lines.join("")}data: [DONE]\n`;
}

function toolCallDelta(name: string, args: Record<string, unknown>) {
  return {
    tool_calls: [
      {
        index: 0,
        id: "call_1",
        type: "function",
        function: { name, arguments: JSON.stringify(args) },
      },
    ],
  };
}

/** Queue one mocked DeepSeek response; optionally capture the request body. */
function mockDeepSeek(body: string, capture?: (requestBody: string) => void) {
  fetchMock
    .get("https://api.deepseek.com")
    .intercept({ path: "/chat/completions", method: "POST" })
    .reply(
      200,
      (opts) => {
        capture?.(String(opts.body));
        return body;
      },
      { headers: { "content-type": "text/event-stream" } }
    );
}

/** Parse our worker's SSE output into { event, data } pairs. */
async function events(res: Response): Promise<{ event: string; data: any }[]> {
  const text = await res.text();
  const out: { event: string; data: any }[] = [];
  for (const block of text.split("\n\n")) {
    let event = "message";
    let data = "";
    for (const line of block.split("\n")) {
      if (line.startsWith("event:")) event = line.slice(6).trim();
      else if (line.startsWith("data:")) data += line.slice(5).trim();
    }
    if (data) out.push({ event, data: JSON.parse(data) });
  }
  return out;
}

describe("ai chat basics", () => {
  it("requires auth", async () => {
    const res = await app.request(
      "/api/ai/chat",
      { method: "POST", body: "{}" },
      env
    );
    expect(res.status).toBe(401);
  });

  it("runs vault-wide when no entity_id is given", async () => {
    mockDeepSeek(completion({ content: "Hello" }));
    const res = await req("/api/ai/chat", {
      method: "POST",
      body: JSON.stringify({ messages: [{ role: "user", content: "Hi" }] }),
    });
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toContain("text/event-stream");

    const evs = await events(res);
    expect(evs.at(-1)?.event).toBe("done");
  });

  it("404s on an unknown entity", async () => {
    const res = await chat("nope");
    expect(res.status).toBe(404);
  });

  it("streams text deltas and a done event", async () => {
    const guli = await create({ name: "Guli", type: "character" });
    mockDeepSeek(completion({ content: "Hello" }, { content: " writer" }));

    const res = await chat(guli.id);
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toContain("text/event-stream");

    const evs = await events(res);
    const text = evs
      .filter((e) => e.event === "text")
      .map((e) => e.data.delta)
      .join("");
    expect(text).toBe("Hello writer");
    expect(evs.at(-1)?.event).toBe("done");
  });

  it("uses the key, URL, and model saved in settings over env vars", async () => {
    const guli = await create({ name: "Guli", type: "character" });
    await req("/api/settings/ai", {
      method: "PUT",
      body: JSON.stringify({
        api_key: "sk-from-settings",
        api_url: "https://ai.example.com",
        model: "custom-model",
      }),
    });

    let auth = "";
    let sent = "";
    fetchMock
      .get("https://ai.example.com")
      .intercept({ path: "/chat/completions", method: "POST" })
      .reply(
        200,
        (opts) => {
          auth = String((opts.headers as Record<string, string>).authorization ?? "");
          sent = String(opts.body);
          return completion({ content: "Ok" });
        },
        { headers: { "content-type": "text/event-stream" } }
      );

    const evs = await events(await chat(guli.id));
    expect(evs.at(-1)?.event).toBe("done");
    expect(auth).toBe("Bearer sk-from-settings");
    expect(JSON.parse(sent).model).toBe("custom-model");
  });

  it("injects the entity's context into the system prompt", async () => {
    const town = await create({ name: "Bangsur Town", type: "location" });
    const guli = await create({
      name: "Guli",
      type: "character",
      content: "Grew up in [[bangsur-town]].",
    });
    await req("/api/relationships", {
      method: "POST",
      body: JSON.stringify({
        source_id: guli.id,
        target_id: town.id,
        type: "born_in",
      }),
    });

    let sent = "";
    mockDeepSeek(completion({ content: "Ok" }), (body) => (sent = body));
    await (await chat(guli.id)).text();

    const parsed = JSON.parse(sent);
    expect(parsed.model).toBe("deepseek-chat");
    expect(parsed.stream).toBe(true);
    const system = parsed.messages[0];
    expect(system.role).toBe("system");
    expect(system.content).toContain("Grew up in [[bangsur-town]].");
    expect(system.content).toContain("born_in");
    expect(system.content).toContain("Bangsur Town");
  });
});

describe("read tools", () => {
  it("executes get_entity and feeds the result back", async () => {
    const guli = await create({ name: "Guli", type: "character" });
    await create({
      name: "Mira",
      type: "character",
      summary: "Guli's rival from the coast",
    });

    mockDeepSeek(completion(toolCallDelta("get_entity", { id_or_slug: "mira" })));
    let second = "";
    mockDeepSeek(completion({ content: "Mira is the rival." }), (b) => (second = b));

    const evs = await events(await chat(guli.id, "Who is Mira?"));

    const reading = evs.find((e) => e.event === "reading");
    expect(reading?.data.tool).toBe("get_entity");
    expect(reading?.data.detail).toContain("mira");

    const parsed = JSON.parse(second);
    const toolMsg = parsed.messages.find((m: any) => m.role === "tool");
    expect(toolMsg.tool_call_id).toBe("call_1");
    expect(toolMsg.content).toContain("Guli's rival from the coast");
    expect(evs.at(-1)?.event).toBe("done");
  });

  it("reports a missing entity to the model instead of failing", async () => {
    const guli = await create({ name: "Guli", type: "character" });
    mockDeepSeek(completion(toolCallDelta("get_entity", { id_or_slug: "ghost" })));
    let second = "";
    mockDeepSeek(completion({ content: "Not found." }), (b) => (second = b));

    const evs = await events(await chat(guli.id));
    expect(evs.at(-1)?.event).toBe("done");
    const toolMsg = JSON.parse(second).messages.find((m: any) => m.role === "tool");
    expect(toolMsg.content).toContain("No entity found");
  });
});

describe("write tools become proposals", () => {
  it("intercepts update_entity and emits a proposal, never writing", async () => {
    const guli = await create({
      name: "Guli",
      type: "character",
      content: "Old prose.",
    });

    mockDeepSeek(
      completion(
        toolCallDelta("update_entity", {
          id_or_slug: "guli",
          change_summary: "Rewrite the backstory around the Bangsur fire",
          content: "New prose about [[bangsur-town]].",
        })
      )
    );
    let second = "";
    mockDeepSeek(completion({ content: "Proposed it." }), (b) => (second = b));

    const evs = await events(await chat(guli.id, "Rewrite it"));

    const proposal = evs.find((e) => e.event === "proposal")?.data;
    expect(proposal.id).toMatch(/^p_/);
    expect(proposal.tool).toBe("update_entity");
    expect(proposal.summary).toBe("Rewrite the backstory around the Bangsur fire");
    // args is the exact PUT body, keyed by the resolved opaque id
    expect(proposal.args.id).toBe(guli.id);
    expect(proposal.args.content).toBe("New prose about [[bangsur-town]].");

    // the model is told it is pending, and the database is untouched
    const toolMsg = JSON.parse(second).messages.find((m: any) => m.role === "tool");
    expect(toolMsg.content).toContain("pending");
    const fetched = await req(`/api/entities/${guli.id}`).then((r) =>
      r.json<Record<string, any>>()
    );
    expect(fetched.content).toBe("Old prose.");
  });

  it("forces create_entity proposals to draft", async () => {
    const guli = await create({ name: "Guli", type: "character" });
    mockDeepSeek(
      completion(
        toolCallDelta("create_entity", {
          change_summary: "Add Mira",
          type: "character",
          name: "Mira",
          summary: "The rival",
        })
      )
    );
    mockDeepSeek(completion({ content: "Done proposing." }));

    const evs = await events(await chat(guli.id));
    const proposal = evs.find((e) => e.event === "proposal")?.data;
    expect(proposal.tool).toBe("create_entity");
    expect(proposal.args.status).toBe("draft");
    expect(proposal.args.name).toBe("Mira");
  });

  it("relays apply_proposal to the client without executing anything", async () => {
    const guli = await create({ name: "Guli", type: "character" });
    mockDeepSeek(
      completion(toolCallDelta("apply_proposal", { proposal_id: "p_abc123" }))
    );
    mockDeepSeek(completion({ content: "Applying." }));

    const evs = await events(await chat(guli.id, "apply it"));
    const proposal = evs.find((e) => e.event === "proposal")?.data;
    expect(proposal.tool).toBe("apply_proposal");
    expect(proposal.args.id).toBe("p_abc123");
  });

  it("refuses to relay apply_proposal for a proposal created the same turn", async () => {
    const guli = await create({
      name: "Guli",
      type: "character",
      content: "Old prose.",
    });

    // Round 1: the model proposes an edit.
    mockDeepSeek(
      completion(
        toolCallDelta("update_entity", {
          id_or_slug: "guli",
          change_summary: "Rewrite",
          content: "New prose.",
        })
      )
    );
    // Round 2: it immediately tries to apply its own proposal, lifting the
    // id from the tool result it just received.
    fetchMock
      .get("https://api.deepseek.com")
      .intercept({ path: "/chat/completions", method: "POST" })
      .reply(
        200,
        (opts) => {
          const msgs = JSON.parse(String(opts.body)).messages;
          const toolMsg = msgs.find((m: any) => m.role === "tool");
          const id = /p_\w+/.exec(toolMsg.content)![0];
          return completion(toolCallDelta("apply_proposal", { proposal_id: id }));
        },
        { headers: { "content-type": "text/event-stream" } }
      );
    // Round 3: it gets the refusal and reports back.
    let third = "";
    mockDeepSeek(completion({ content: "It awaits your approval." }), (b) => (third = b));

    const evs = await events(await chat(guli.id, "Rewrite it"));

    // Only the update_entity proposal reaches the client — no relay event.
    const proposals = evs.filter((e) => e.event === "proposal");
    expect(proposals).toHaveLength(1);
    expect(proposals[0].data.tool).toBe("update_entity");

    const toolMsgs = JSON.parse(third).messages.filter((m: any) => m.role === "tool");
    expect(toolMsgs.at(-1).content).toContain("has not seen it");
    expect(evs.at(-1)?.event).toBe("done");
  });

  it("feeds invalid tool arguments back as an error result", async () => {
    const guli = await create({ name: "Guli", type: "character" });
    // update with no fields to change
    mockDeepSeek(
      completion(
        toolCallDelta("update_entity", {
          id_or_slug: "guli",
          change_summary: "Nothing",
        })
      )
    );
    let second = "";
    mockDeepSeek(completion({ content: "Oops." }), (b) => (second = b));

    const evs = await events(await chat(guli.id));
    expect(evs.find((e) => e.event === "proposal")).toBeUndefined();
    const toolMsg = JSON.parse(second).messages.find((m: any) => m.role === "tool");
    expect(toolMsg.content).toContain("Error");
  });
});
