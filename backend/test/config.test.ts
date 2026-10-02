import { loadConfig } from "../src/config";

const validToken = "a".repeat(40);

describe("loadConfig", () => {
  it("nutzt sichere Standardwerte (nur localhost, Port 3000)", () => {
    const config = loadConfig({ API_TOKEN: validToken });

    expect(config).toMatchObject({
      env: "development",
      host: "127.0.0.1",
      port: 3000,
      apiToken: validToken,
      logLevel: "info"
    });
  });

  it("uebernimmt gesetzte Werte", () => {
    const config = loadConfig({
      API_TOKEN: validToken,
      NODE_ENV: "production",
      HOST: "0.0.0.0",
      PORT: "8080",
      LOG_LEVEL: "debug"
    });

    expect(config).toMatchObject({ env: "production", host: "0.0.0.0", port: 8080, logLevel: "debug" });
  });

  it("verweigert den Start ohne API_TOKEN", () => {
    expect(() => loadConfig({})).toThrow("API_TOKEN");
    expect(() => loadConfig({ API_TOKEN: "   " })).toThrow("API_TOKEN");
  });

  it("verlangt in Produktion einen langen Token, in Entwicklung nicht", () => {
    expect(() => loadConfig({ API_TOKEN: "kurz", NODE_ENV: "production" })).toThrow("zu kurz");
    expect(loadConfig({ API_TOKEN: "kurz", NODE_ENV: "development" }).apiToken).toBe("kurz");
  });

  it("verweigert ungueltige Ports", () => {
    for (const port of ["0", "70000", "abc", "3.5", "-1"]) {
      expect(() => loadConfig({ API_TOKEN: validToken, PORT: port })).toThrow("PORT");
    }
  });

  it("verweigert ein unbekanntes NODE_ENV", () => {
    expect(() => loadConfig({ API_TOKEN: validToken, NODE_ENV: "staging" })).toThrow("NODE_ENV");
  });

  it("schaltet das Logging im Test-Modus stumm", () => {
    expect(loadConfig({ API_TOKEN: validToken, NODE_ENV: "test" }).logLevel).toBe("silent");
  });
});

describe("loadConfig: Claude und Plan", () => {
  it("nutzt Standardwerte: Opus 5.5, Effort high, 75 s Zeitlimit, Server-Fallback an", () => {
    const config = loadConfig({ API_TOKEN: validToken });

    expect(config).toMatchObject({
      anthropicApiKey: undefined,
      claudeModel: "claude-opus-5-5",
      claudeEffort: "high",
      claudeTimeoutMs: 75_000,
      claudeServerFallback: true,
      dataDir: "./data",
      planTimezone: "Europe/Berlin",
      maxGenerationsPerHour: 5,
      maxGenerationsPerDay: 20
    });
  });

  it("startet auch ohne ANTHROPIC_API_KEY (dann liefert der Plan-Endpunkt nur gespeicherte Plaene)", () => {
    expect(loadConfig({ API_TOKEN: validToken }).anthropicApiKey).toBeUndefined();
    expect(loadConfig({ API_TOKEN: validToken, ANTHROPIC_API_KEY: "   " }).anthropicApiKey).toBeUndefined();
  });

  it("uebernimmt gesetzte Werte", () => {
    const config = loadConfig({
      API_TOKEN: validToken,
      ANTHROPIC_API_KEY: "sk-ant-test",
      PLAN_MODEL: "claude-sonnet-5-5",
      PLAN_EFFORT: "high",
      PLAN_TIMEOUT_MS: "60000",
      PLAN_SERVER_FALLBACK: "false",
      DATA_DIR: "/data",
      PLAN_TIMEZONE: "America/New_York",
      PLAN_MAX_GENERATIONS_PER_HOUR: "3",
      PLAN_MAX_GENERATIONS_PER_DAY: "10"
    });

    expect(config).toMatchObject({
      anthropicApiKey: "sk-ant-test",
      claudeModel: "claude-sonnet-5-5",
      claudeEffort: "high",
      claudeTimeoutMs: 60_000,
      claudeServerFallback: false,
      dataDir: "/data",
      planTimezone: "America/New_York",
      maxGenerationsPerHour: 3,
      maxGenerationsPerDay: 10
    });
  });

  it.each([
    ["PLAN_EFFORT", "extrem"],
    ["PLAN_TIMEOUT_MS", "abc"],
    ["PLAN_TIMEOUT_MS", "500"],
    ["PLAN_TIMEOUT_MS", "120000"],
    ["PLAN_SERVER_FALLBACK", "vielleicht"],
    ["PLAN_TIMEZONE", "Mars/Olympus"],
    ["PLAN_MAX_GENERATIONS_PER_HOUR", "0"],
    ["PLAN_MAX_GENERATIONS_PER_DAY", "1.5"]
  ])("verweigert den Start bei ungueltigem %s=%s", (name, value) => {
    expect(() => loadConfig({ API_TOKEN: validToken, [name]: value })).toThrow(name);
  });

  it("akzeptiert 1 und 0 als Wahrheitswerte", () => {
    expect(loadConfig({ API_TOKEN: validToken, PLAN_SERVER_FALLBACK: "0" }).claudeServerFallback).toBe(false);
    expect(loadConfig({ API_TOKEN: validToken, PLAN_SERVER_FALLBACK: "1" }).claudeServerFallback).toBe(true);
  });

  it("ignoriert die Umgebungsvariablen von Claude Code selbst (CLAUDE_EFFORT, CLAUDE_MODEL)", () => {
    // Claude Code setzt solche Variablen in seiner eigenen Umgebung. Sie duerfen den Server nie beeinflussen.
    const config = loadConfig({ API_TOKEN: validToken, CLAUDE_EFFORT: "max", CLAUDE_MODEL: "irgendwas", CLAUDE_TIMEOUT_MS: "abc" });

    expect(config.claudeEffort).toBe("high");
    expect(config.claudeModel).toBe("claude-opus-5-5");
    expect(config.claudeTimeoutMs).toBe(75_000);
  });
});

