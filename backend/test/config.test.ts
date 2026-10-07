import { loadConfig, planTimeouts } from "../src/config";

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
  it("nutzt Standardwerte: Opus 5.5, Effort high, 75 s Zeitlimit (180 s fuer den Gesamtplan), Server-Fallback an", () => {
    const config = loadConfig({ API_TOKEN: validToken });

    expect(config).toMatchObject({
      anthropicApiKey: undefined,
      claudeModel: "claude-opus-5-5",
      claudeEffort: "high",
      claudeTimeoutMs: 75_000,
      claudeMacroTimeoutMs: 180_000,
      claudeServerFallback: true,
      dataDir: "./data",
      planTimezone: "Europe/Berlin",
      maxGenerationsPerHour: 10,
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
      PLAN_MACRO_TIMEOUT_MS: "200000",
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
      claudeMacroTimeoutMs: 200_000,
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
    ["PLAN_MACRO_TIMEOUT_MS", "abc"],
    ["PLAN_MACRO_TIMEOUT_MS", "240000"],
    ["PLAN_SERVER_FALLBACK", "vielleicht"],
    ["PLAN_TIMEZONE", "Mars/Olympus"],
    ["PLAN_MAX_GENERATIONS_PER_HOUR", "0"],
    ["PLAN_MAX_GENERATIONS_PER_DAY", "1.5"]
  ])("verweigert den Start bei ungueltigem %s=%s", (name, value) => {
    expect(() => loadConfig({ API_TOKEN: validToken, [name]: value })).toThrow(name);
  });

  it("liefert die Zeitlimits auch ohne die restliche Konfiguration (fuer die Bewertungsskripte)", () => {
    expect(planTimeouts({})).toEqual({ claudeTimeoutMs: 75_000, claudeMacroTimeoutMs: 180_000 });
    expect(planTimeouts({ PLAN_TIMEOUT_MS: "80000", PLAN_MACRO_TIMEOUT_MS: "230000" })).toEqual({ claudeTimeoutMs: 80_000, claudeMacroTimeoutMs: 230_000 });
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


describe("loadConfig: Nutzer-Budget und Alarme", () => {
  it("hat ein Gesamtbudget fuer den Server und ohne Webhook keine Alarme", () => {
    const config = loadConfig({ API_TOKEN: validToken });

    expect(config.maxGenerationsTotalPerHour).toBe(15);
    expect(config.maxGenerationsTotalPerDay).toBe(60);
    expect(config.alerts).toBeUndefined();
  });

  it("liest die Alarme mit Standardschwellen und erkennt ntfy an der Adresse", () => {
    const config = loadConfig({ API_TOKEN: validToken, ALERT_WEBHOOK_URL: "https://ntfy.sh/geheim", PLAN_MAX_GENERATIONS_TOTAL_PER_DAY: "100" });

    expect(config.maxGenerationsTotalPerDay).toBe(100);
    expect(config.alerts).toEqual({ webhookUrl: "https://ntfy.sh/geheim", format: "ntfy", dailyCostUsd: 5, failuresPerHour: 3, failureRate: 0.5 });
  });

  it("uebernimmt Format und Schwellen", () => {
    const config = loadConfig({
      API_TOKEN: validToken,
      ALERT_WEBHOOK_URL: "https://hooks.slack.com/services/x",
      ALERT_WEBHOOK_FORMAT: "slack",
      ALERT_DAILY_COST_USD: "2.5",
      ALERT_FAILURES_PER_HOUR: "5",
      ALERT_FAILURE_RATE: "0.8"
    });

    expect(config.alerts).toEqual({ webhookUrl: "https://hooks.slack.com/services/x", format: "slack", dailyCostUsd: 2.5, failuresPerHour: 5, failureRate: 0.8 });
    expect(loadConfig({ API_TOKEN: validToken, ALERT_WEBHOOK_URL: "https://example.test/hook" }).alerts?.format).toBe("json");
  });

  it("verweigert unsinnige Alarm-Einstellungen", () => {
    expect(() => loadConfig({ API_TOKEN: validToken, ALERT_WEBHOOK_URL: "kein-url" })).toThrow("ALERT_WEBHOOK_URL");
    expect(() => loadConfig({ API_TOKEN: validToken, ALERT_WEBHOOK_URL: "ftp://example.test" })).toThrow("https://");
    expect(() => loadConfig({ API_TOKEN: validToken, ALERT_WEBHOOK_URL: "https://example.test", ALERT_WEBHOOK_FORMAT: "teams" })).toThrow("ALERT_WEBHOOK_FORMAT");
    expect(() => loadConfig({ API_TOKEN: validToken, ALERT_WEBHOOK_URL: "https://example.test", ALERT_FAILURE_RATE: "2" })).toThrow("ALERT_FAILURE_RATE");
    expect(() => loadConfig({ API_TOKEN: validToken, PLAN_MAX_GENERATIONS_TOTAL_PER_HOUR: "0" })).toThrow("PLAN_MAX_GENERATIONS_TOTAL_PER_HOUR");
  });
});
