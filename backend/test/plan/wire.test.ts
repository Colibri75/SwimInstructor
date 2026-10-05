import Anthropic from "@anthropic-ai/sdk";
import http from "node:http";
import { AddressInfo } from "node:net";
import { PlanGenerationError } from "../../src/plan/errors";
import { ClaudePlanGenerator } from "../../src/plan/generator";
import { MULTI_DAY_SYSTEM_PROMPT } from "../../src/plan/multi/prompts";
import { MultiDayPlanSchema } from "../../src/plan/multi/schemas";

const raw = { rationale: "Lockerer Tag.", sessions: [], coach_notes: [] };

/**
 * Das echte Anthropic-SDK spricht hier ueber HTTP mit einem lokalen Fake-Server. So pruefen wir das
 * tatsaechliche Anfrageformat (Pfad, Header, Body) und die echten Fehlerklassen des SDK, nicht nur
 * einen gemockten Client.
 */
interface Captured {
  method?: string;
  url?: string;
  headers: http.IncomingHttpHeaders;
  body: Record<string, unknown>;
}

let server: http.Server;
let baseURL: string;
let captured: Captured | null;
let respond: (req: http.IncomingMessage, res: http.ServerResponse) => void;
const sockets = new Set<import("node:net").Socket>();

const messageBody = (text: string, extra: Record<string, unknown> = {}) =>
  JSON.stringify({
    id: "msg_test",
    type: "message",
    role: "assistant",
    model: "claude-opus-5-5",
    content: [{ type: "text", text }],
    stop_reason: "end_turn",
    stop_sequence: null,
    usage: { input_tokens: 1800, output_tokens: 2500 },
    ...extra
  });

beforeAll(async () => {
  server = http.createServer((req, res) => {
    const chunks: Buffer[] = [];
    req.on("data", (chunk: Buffer) => chunks.push(chunk));
    req.on("end", () => {
      captured = { method: req.method, url: req.url, headers: req.headers, body: JSON.parse(Buffer.concat(chunks).toString() || "{}") };
      respond(req, res);
    });
  });
  server.on("connection", (socket) => {
    sockets.add(socket);
    socket.on("close", () => sockets.delete(socket));
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  baseURL = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});

afterAll(async () => {
  sockets.forEach((socket) => socket.destroy());
  await new Promise<void>((resolve) => server.close(() => resolve()));
});

beforeEach(() => {
  captured = null;
  respond = (_req, res) => {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(messageBody(JSON.stringify(raw)));
  };
});

const generator = (timeoutMs = 5_000, url = baseURL) =>
  new ClaudePlanGenerator(new Anthropic({ apiKey: "test-key", baseURL: url }), {
    model: "claude-opus-5-5",
    timeoutMs,
    macroTimeoutMs: timeoutMs,
    effort: "medium",
    serverFallback: true
  });
const generate = (g: ClaudePlanGenerator) => g.complete(MULTI_DAY_SYSTEM_PROMPT, "Erstelle die Einheiten für heute, Mittwoch, 2026-09-30.", MultiDayPlanSchema);

describe("ClaudePlanGenerator ueber echtes HTTP: Anfrageformat", () => {
  it("sendet eine gueltige Messages-Anfrage mit Beta-Header, Schema und festem System-Prompt", async () => {
    await generate(generator());

    expect(captured?.method).toBe("POST");
    expect(captured?.url).toContain("/v1/messages");
    expect(captured?.headers["x-api-key"]).toBe("test-key");
    expect(captured?.headers["anthropic-beta"]).toContain("server-side-fallback-2026-07-01");

    const body = captured!.body as Record<string, any>;
    expect(body.model).toBe("claude-opus-5-5");
    expect(body.fallbacks).toBe("default");
    expect(body.thinking).toEqual({ type: "adaptive" });
    expect(body.system).toBe(MULTI_DAY_SYSTEM_PROMPT);
    expect(body.output_config.effort).toBe("medium");
    expect(body.output_config.format.type).toBe("json_schema");
    expect(body.output_config.format.schema.type).toBe("object");
    expect(body.output_config.format.schema.properties.sessions.type).toBe("array");
    expect(body.output_config.format.schema.required).toEqual(expect.arrayContaining(["rationale", "sessions", "coach_notes"]));
    expect(body.tool_choice).toBeUndefined();
    expect(body.messages[0].content).toContain("Mittwoch, 2026-09-30");
  });

  it("liest die Antwort des Servers: Plan, Modell und Token-Verbrauch", async () => {
    const result = await generate(generator());

    expect(result.raw).toEqual(raw);
    expect(result.model).toBe("claude-opus-5-5");
    expect(result.usage).toEqual({ inputTokens: 1800, outputTokens: 2500 });
  });

  it("wiederholt bei einem Fehler nicht selbst (nur ein Request, keine doppelten Kosten)", async () => {
    let requests = 0;
    respond = (_req, res) => {
      requests++;
      res.writeHead(500, { "content-type": "application/json" });
      res.end(JSON.stringify({ type: "error", error: { type: "api_error", message: "kaputt" } }));
    };

    await expect(generate(generator())).rejects.toMatchObject({ reason: "upstream_error" });
    expect(requests).toBe(1);
  });
});

describe("ClaudePlanGenerator ueber echtes HTTP: Fehlerfaelle", () => {
  const failWith = (status: number, type: string) => {
    respond = (_req, res) => {
      res.writeHead(status, { "content-type": "application/json" });
      res.end(JSON.stringify({ type: "error", error: { type, message: "fehler" } }));
    };
  };

  it.each([
    [429, "rate_limit_error", "rate_limited"],
    [500, "api_error", "upstream_error"],
    [529, "overloaded_error", "upstream_error"],
    [401, "authentication_error", "auth"],
    [403, "permission_error", "auth"],
    [400, "invalid_request_error", "bad_request"]
  ])("ordnet HTTP %i (%s) dem Grund %s zu", async (status, type, reason) => {
    failWith(status, type);

    const failure = await generate(generator()).catch((error: unknown) => error);

    expect(failure).toBeInstanceOf(PlanGenerationError);
    expect((failure as PlanGenerationError).reason).toBe(reason);
  });

  it("meldet 'unreachable', wenn niemand auf dem Port lauscht", async () => {
    const closed = http.createServer();
    await new Promise<void>((resolve) => closed.listen(0, "127.0.0.1", resolve));
    const url = `http://127.0.0.1:${(closed.address() as AddressInfo).port}`;
    await new Promise<void>((resolve) => closed.close(() => resolve()));

    const failure = await generate(generator(5_000, url)).catch((error: unknown) => error);

    expect((failure as PlanGenerationError).reason).toBe("unreachable");
  });

  it("meldet 'timeout', wenn der Server zu langsam antwortet", async () => {
    respond = (_req, res) => {
      setTimeout(() => {
        res.writeHead(200, { "content-type": "application/json" });
        res.end(messageBody(JSON.stringify(raw)));
      }, 1_500);
    };

    const failure = await generate(generator(150)).catch((error: unknown) => error);

    expect((failure as PlanGenerationError).reason).toBe("timeout");
  });

  it("meldet 'invalid_json', wenn der Server Text statt JSON liefert", async () => {
    respond = (_req, res) => {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(messageBody("Heute schwimmst du 2 km, viel Erfolg!"));
    };

    await expect(generate(generator())).rejects.toMatchObject({ reason: "invalid_json" });
  });

  it("meldet 'refusal', wenn Claude ablehnt", async () => {
    respond = (_req, res) => {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(messageBody("", { content: [], stop_reason: "refusal", stop_details: { type: "refusal", category: "cyber", explanation: null } }));
    };

    await expect(generate(generator())).rejects.toMatchObject({ reason: "refusal" });
  });
});
