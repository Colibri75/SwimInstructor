export type Environment = "development" | "production" | "test";

export type Effort = "low" | "medium" | "high" | "xhigh" | "max";

export interface Config {
  env: Environment;
  host: string;
  port: number;
  apiToken: string;
  logLevel: string;
  /** Ohne Key startet der Server trotzdem. `/v1/plan/today` liefert dann nur Cache und Fallback. */
  anthropicApiKey: string | undefined;
  claudeModel: string;
  claudeEffort: Effort;
  /** Zeitlimit fuer Tages- und Wochenplaene. */
  claudeTimeoutMs: number;
  /** Zeitlimit fuer Gesamtplaene und ihre Ueberarbeitung. */
  claudeMacroTimeoutMs: number;
  /** Server-seitiger Fallback bei Ablehnung durch Claudes Sicherheitsklassifikatoren. */
  claudeServerFallback: boolean;
  /** Verzeichnis fuer den letzten gueltigen Plan (im Container das Volume /data). */
  dataDir: string;
  planTimezone: string;
  maxGenerationsPerHour: number;
  maxGenerationsPerDay: number;
}

const MIN_PRODUCTION_TOKEN_LENGTH = 32;

/**
 * Liest und validiert die Konfiguration aus den Umgebungsvariablen. Wirft bei fehlenden oder
 * unsinnigen Werten, damit der Server gar nicht erst mit einer unsicheren Konfiguration startet.
 */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const environment = parseEnvironment(env.NODE_ENV);

  const apiToken = env.API_TOKEN?.trim();
  if (!apiToken) {
    throw new Error("API_TOKEN ist nicht gesetzt (erzeugen mit: openssl rand -hex 32)");
  }
  if (environment === "production" && apiToken.length < MIN_PRODUCTION_TOKEN_LENGTH) {
    throw new Error(`API_TOKEN ist zu kurz: in Produktion mindestens ${MIN_PRODUCTION_TOKEN_LENGTH} Zeichen`);
  }

  return {
    env: environment,
    host: env.HOST?.trim() || "127.0.0.1",
    port: parsePort(env.PORT),
    apiToken,
    logLevel: env.LOG_LEVEL?.trim() || (environment === "test" ? "silent" : "info"),
    anthropicApiKey: env.ANTHROPIC_API_KEY?.trim() || undefined,
    claudeModel: env.PLAN_MODEL?.trim() || "claude-opus-5-5",
    claudeEffort: parseEffort(env.PLAN_EFFORT),
    ...planTimeouts(env),
    claudeServerFallback: parseBoolean("PLAN_SERVER_FALLBACK", env.PLAN_SERVER_FALLBACK, true),
    dataDir: env.DATA_DIR?.trim() || "./data",
    planTimezone: parseTimezone(env.PLAN_TIMEZONE),
    maxGenerationsPerHour: parseInteger("PLAN_MAX_GENERATIONS_PER_HOUR", env.PLAN_MAX_GENERATIONS_PER_HOUR, 5, 1, 1_000),
    maxGenerationsPerDay: parseInteger("PLAN_MAX_GENERATIONS_PER_DAY", env.PLAN_MAX_GENERATIONS_PER_DAY, 20, 1, 10_000)
  };
}

/**
 * Zeitlimits fuer die Claude-Aufrufe. Eigene Funktion, weil die Bewertungsskripte mit derselben Env-Datei laufen
 * wie der Server und dieselben Grenzen brauchen, aber nicht die ganze Konfiguration (API_TOKEN).
 *
 * Der Server muss vor dem Reverse-Proxy (240 s, deploy/Caddyfile.example) und vor der App aufgeben (95 s fuer
 * Tag und Woche, 245 s fuer den Gesamtplan, PlanAPIClient), sonst kommt statt seiner Antwort nur ein Abbruch an.
 */
export function planTimeouts(env: NodeJS.ProcessEnv = process.env): { claudeTimeoutMs: number; claudeMacroTimeoutMs: number } {
  return {
    // Tag und Woche: 75 s reichen gut (ein Aufruf braucht rund 30 s), hoechstens 85 s wegen der 95 s der App.
    claudeTimeoutMs: parseInteger("PLAN_TIMEOUT_MS", env.PLAN_TIMEOUT_MS, 75_000, 1_000, 85_000),
    // Gesamtplan und Ueberarbeitung: bei drei Sportarten und Effort high oft ueber 80 s, daher 180 s,
    // hoechstens 230 s wegen der 240 s des Reverse-Proxys.
    claudeMacroTimeoutMs: parseInteger("PLAN_MACRO_TIMEOUT_MS", env.PLAN_MACRO_TIMEOUT_MS, 180_000, 1_000, 230_000)
  };
}

function parseEnvironment(value: string | undefined): Environment {
  if (value === undefined || value === "") return "development";
  if (value === "development" || value === "production" || value === "test") return value;
  throw new Error(`NODE_ENV ungueltig: "${value}" (erlaubt: development, production, test)`);
}

function parsePort(value: string | undefined): number {
  if (value === undefined || value.trim() === "") return 3000;
  const port = Number(value);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error(`PORT ungueltig: "${value}" (erlaubt: 1 bis 65535)`);
  }
  return port;
}

function parseEffort(value: string | undefined): Effort {
  if (value === undefined || value.trim() === "") return "high";
  const effort = value.trim();
  if (effort === "low" || effort === "medium" || effort === "high" || effort === "xhigh" || effort === "max") return effort;
  throw new Error(`PLAN_EFFORT ungueltig: "${value}" (erlaubt: low, medium, high, xhigh, max)`);
}

function parseInteger(name: string, value: string | undefined, fallback: number, min: number, max: number): number {
  if (value === undefined || value.trim() === "") return fallback;
  const number = Number(value);
  if (!Number.isInteger(number) || number < min || number > max) {
    throw new Error(`${name} ungueltig: "${value}" (erlaubt: ganze Zahl von ${min} bis ${max})`);
  }
  return number;
}

function parseBoolean(name: string, value: string | undefined, fallback: boolean): boolean {
  if (value === undefined || value.trim() === "") return fallback;
  const normalized = value.trim().toLowerCase();
  if (normalized === "true" || normalized === "1") return true;
  if (normalized === "false" || normalized === "0") return false;
  throw new Error(`${name} ungueltig: "${value}" (erlaubt: true oder false)`);
}

function parseTimezone(value: string | undefined): string {
  const timezone = value?.trim() || "Europe/Berlin";
  try {
    new Intl.DateTimeFormat("en-CA", { timeZone: timezone });
  } catch {
    throw new Error(`PLAN_TIMEZONE ungueltig: "${timezone}" (IANA-Name wie Europe/Berlin erwartet)`);
  }
  return timezone;
}
