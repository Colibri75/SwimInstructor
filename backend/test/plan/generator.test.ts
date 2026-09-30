import Anthropic from "@anthropic-ai/sdk";
import { ClaudeOptions, ClaudePlanGenerator } from "../../src/plan/generator";
import { PlanGenerationError } from "../../src/plan/errors";
import { SYSTEM_PROMPT } from "../../src/plan/prompt";
import { goodPlan, snapshot } from "./fixtures";

const options: ClaudeOptions = { model: "claude-opus-5-5", timeoutMs: 75_000, effort: "medium", serverFallback: true };
const input = { snapshot: snapshot(), date: "2026-09-30" };

function response(overrides: Record<string, unknown> = {}) {
  return {
    model: "claude-opus-5-5",
    stop_reason: "end_turn",
    stop_details: null,
    content: [{ type: "text", text: JSON.stringify(goodPlan) }],
    usage: { input_tokens: 1800, output_tokens: 2500 },
    ...overrides
  };
}

function generatorWith(create: jest.Mock, custom: Partial<ClaudeOptions> = {}): ClaudePlanGenerator {
  const client = { beta: { messages: { create } } } as unknown as Anthropic;
  return new ClaudePlanGenerator(client, { ...options, ...custom });
}

function apiError(status: number, type: string, message = "fehler"): Error {
  return Anthropic.APIError.generate(status, { type: "error", error: { type, message } }, message, new Headers());
}

describe("ClaudePlanGenerator: Anfrage", () => {
  it("sendet Modell, festen System-Prompt, strukturierte Ausgabe und Effort", async () => {
    const create = jest.fn().mockResolvedValue(response());

    await generatorWith(create).generate(input);

    const [body, requestOptions] = create.mock.calls[0];
    expect(body.model).toBe("claude-opus-5-5");
    expect(body.system).toBe(SYSTEM_PROMPT);
    expect(body.thinking).toEqual({ type: "adaptive" });
    expect(body.output_config.effort).toBe("medium");
    expect(body.output_config.format.type).toBe("json_schema");
    expect(body.output_config.format.schema.properties).toHaveProperty("sets");
    expect(body.messages).toHaveLength(1);
    expect(body.messages[0].role).toBe("user");
    expect(body.messages[0].content).toContain("Mittwoch, 2026-09-30");
    expect(requestOptions).toEqual({ timeout: 75_000, maxRetries: 0 });
  });

  it("erzwingt kein Tool (forcierte Tool-Aufrufe sind auf diesem Modell verboten)", async () => {
    const create = jest.fn().mockResolvedValue(response());

    await generatorWith(create).generate(input);

    expect(create.mock.calls[0][0].tool_choice).toBeUndefined();
    expect(create.mock.calls[0][0].tools).toBeUndefined();
  });

  it("schaltet den Server-Fallback bei Ablehnung standardmaessig ein", async () => {
    const create = jest.fn().mockResolvedValue(response());

    await generatorWith(create).generate(input);

    const body = create.mock.calls[0][0];
    expect(body.fallbacks).toBe("default");
    expect(body.betas).toEqual(["server-side-fallback-2026-07-01"]);
  });

  it("laesst den Server-Fallback weg, wenn er abgeschaltet ist", async () => {
    const create = jest.fn().mockResolvedValue(response());

    await generatorWith(create, { serverFallback: false }).generate(input);

    const body = create.mock.calls[0][0];
    expect(body.fallbacks).toBeUndefined();
    expect(body.betas).toBeUndefined();
  });

  it("reicht Modell und Effort aus der Konfiguration durch", async () => {
    const create = jest.fn().mockResolvedValue(response());

    await generatorWith(create, { model: "claude-sonnet-5-5", effort: "high" }).generate(input);

    expect(create.mock.calls[0][0].model).toBe("claude-sonnet-5-5");
    expect(create.mock.calls[0][0].output_config.effort).toBe("high");
  });
});

describe("ClaudePlanGenerator: Antwort", () => {
  it("liefert das geparste JSON, das tatsaechliche Modell und den Verbrauch", async () => {
    const create = jest.fn().mockResolvedValue(response({ model: "claude-opus-4-8" }));

    const result = await generatorWith(create).generate(input);

    expect(result.raw).toEqual(goodPlan);
    expect(result.model).toBe("claude-opus-4-8");
    expect(result.usage).toEqual({ inputTokens: 1800, outputTokens: 2500 });
  });

  it("ueberspringt thinking-Bloecke und liest den Text-Block", async () => {
    const create = jest.fn().mockResolvedValue(
      response({ content: [{ type: "thinking", thinking: "" }, { type: "text", text: JSON.stringify(goodPlan) }] })
    );

    expect((await generatorWith(create).generate(input)).raw).toEqual(goodPlan);
  });

  it.each([
    ["Ablehnung durch Claude", response({ stop_reason: "refusal", stop_details: { type: "refusal", category: "cyber" } }), "refusal"],
    ["abgeschnittene Antwort", response({ stop_reason: "max_tokens" }), "truncated"],
    ["leere Antwort", response({ content: [] }), "empty_response"],
    ["nur ein thinking-Block", response({ content: [{ type: "thinking", thinking: "" }] }), "empty_response"],
    ["Text ohne JSON", response({ content: [{ type: "text", text: "Hier ist dein Plan: viel Spaß!" }] }), "invalid_json"],
    ["halb abgebrochenes JSON", response({ content: [{ type: "text", text: '{"session_type": "rest", ' }] }), "invalid_json"]
  ])("meldet %s als %s", async (_name, reply, reason) => {
    const create = jest.fn().mockResolvedValue(reply);

    await expect(generatorWith(create).generate(input)).rejects.toMatchObject({ name: "PlanGenerationError", reason });
  });
});

describe("ClaudePlanGenerator: Fehlerfaelle der API", () => {
  it.each([
    ["Zeitueberschreitung", new Anthropic.APIConnectionTimeoutError(), "timeout"],
    ["API nicht erreichbar", new Anthropic.APIConnectionError({ message: "getaddrinfo ENOTFOUND api.anthropic.com" }), "unreachable"],
    ["Rate-Limit (429)", apiError(429, "rate_limit_error"), "rate_limited"],
    ["falscher API-Key (401)", apiError(401, "authentication_error"), "auth"],
    ["fehlende Berechtigung (403)", apiError(403, "permission_error"), "auth"],
    ["ungueltige Anfrage (400)", apiError(400, "invalid_request_error"), "bad_request"],
    ["Serverfehler (500)", apiError(500, "api_error"), "upstream_error"],
    ["ueberlastet (529)", apiError(529, "overloaded_error"), "upstream_error"],
    ["unbekannter Fehler", new TypeError("boom"), "unknown"]
  ])("ordnet %s dem Grund %s zu", async (_name, error, reason) => {
    const create = jest.fn().mockRejectedValue(error);

    const failure = await generatorWith(create).generate(input).catch((e: unknown) => e);

    expect(failure).toBeInstanceOf(PlanGenerationError);
    expect((failure as PlanGenerationError).reason).toBe(reason);
  });

  it("behaelt die urspruengliche Ursache am Fehler", async () => {
    const original = new Anthropic.APIConnectionTimeoutError();
    const create = jest.fn().mockRejectedValue(original);

    const failure = (await generatorWith(create).generate(input).catch((e: unknown) => e)) as PlanGenerationError;

    expect(failure.cause).toBe(original);
  });
});
