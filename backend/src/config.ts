export type Environment = "development" | "production" | "test";

export type Effort = "low" | "medium" | "high" | "xhigh" | "max";

export type AlertFormat = "ntfy" | "slack" | "discord" | "json";

export interface AlertConfig {
  webhookUrl: string;
  format: AlertFormat;
  dailyCostUsd: number;
  failuresPerHour: number;
  failureRate: number;
}

/**
 * Angaben fuer die Datenschutzerklaerung (`/datenschutz`, `/privacy`). Name, Anschrift und E-Mail haben Standardwerte
 * (`PRIVACY_DEFAULTS`); fehlt eine Angabe trotzdem (Tests), steht dort "[wird ergänzt]".
 */
export interface PrivacyContact {
  name: string | undefined;
  /** Anschrift; `\n` (als zwei Zeichen) oder ein Zeilenumbruch trennt die Zeilen. */
  address: string | undefined;
  email: string | undefined;
  /** Hosting-Anbieter des Servers mit Sitz, z. B. "Hetzner Online GmbH, Gunzenhausen (Deutschland)". */
  hoster: string | undefined;
}

/** Der Verantwortliche, wenn PRIVACY_CONTACT_* nicht gesetzt sind. Den Hoster gibt es nur per PRIVACY_HOSTER. */
export const PRIVACY_DEFAULTS = {
  name: "Steffen Kellner",
  address: "Alfelder Weg 55, 90482 Nürnberg, Deutschland",
  email: "steffen.kellner91@gmail.com"
} as const;

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
  /** Aufrufbudget je Nutzer. */
  maxGenerationsPerHour: number;
  maxGenerationsPerDay: number;
  /** Aufrufbudget des ganzen Servers ueber alle Nutzer (Kostenbremse). */
  maxGenerationsTotalPerHour: number;
  maxGenerationsTotalPerDay: number;
  /** Alarme per Webhook; `undefined` ohne `ALERT_WEBHOOK_URL`. */
  alerts: AlertConfig | undefined;
  privacy: PrivacyContact;
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
    maxGenerationsPerHour: parseInteger("PLAN_MAX_GENERATIONS_PER_HOUR", env.PLAN_MAX_GENERATIONS_PER_HOUR, 10, 1, 1_000),
    maxGenerationsPerDay: parseInteger("PLAN_MAX_GENERATIONS_PER_DAY", env.PLAN_MAX_GENERATIONS_PER_DAY, 20, 1, 10_000),
    maxGenerationsTotalPerHour: parseInteger("PLAN_MAX_GENERATIONS_TOTAL_PER_HOUR", env.PLAN_MAX_GENERATIONS_TOTAL_PER_HOUR, 15, 1, 10_000),
    maxGenerationsTotalPerDay: parseInteger("PLAN_MAX_GENERATIONS_TOTAL_PER_DAY", env.PLAN_MAX_GENERATIONS_TOTAL_PER_DAY, 60, 1, 100_000),
    alerts: parseAlerts(env),
    privacy: {
      name: env.PRIVACY_CONTACT_NAME?.trim() || PRIVACY_DEFAULTS.name,
      address: env.PRIVACY_CONTACT_ADDRESS?.trim() || PRIVACY_DEFAULTS.address,
      email: env.PRIVACY_CONTACT_EMAIL?.trim() || PRIVACY_DEFAULTS.email,
      hoster: env.PRIVACY_HOSTER?.trim() || undefined
    }
  };
}

function parseAlerts(env: NodeJS.ProcessEnv): AlertConfig | undefined {
  const webhookUrl = env.ALERT_WEBHOOK_URL?.trim();
  if (!webhookUrl) return undefined;
  let url: URL;
  try {
    url = new URL(webhookUrl);
  } catch {
    throw new Error("ALERT_WEBHOOK_URL ist keine gueltige URL");
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") throw new Error("ALERT_WEBHOOK_URL muss mit https:// beginnen");
  const formatValue = env.ALERT_WEBHOOK_FORMAT?.trim() || (url.hostname.includes("ntfy") ? "ntfy" : "json");
  if (formatValue !== "ntfy" && formatValue !== "slack" && formatValue !== "discord" && formatValue !== "json") {
    throw new Error(`ALERT_WEBHOOK_FORMAT ungueltig: "${formatValue}" (erlaubt: ntfy, slack, discord, json)`);
  }
  return {
    webhookUrl,
    format: formatValue,
    dailyCostUsd: parseNumber("ALERT_DAILY_COST_USD", env.ALERT_DAILY_COST_USD, 5, 0.01, 10_000),
    failuresPerHour: parseInteger("ALERT_FAILURES_PER_HOUR", env.ALERT_FAILURES_PER_HOUR, 3, 1, 1_000),
    failureRate: parseNumber("ALERT_FAILURE_RATE", env.ALERT_FAILURE_RATE, 0.5, 0.01, 1)
  };
}

function parseNumber(name: string, value: string | undefined, fallback: number, min: number, max: number): number {
  if (value === undefined || value.trim() === "") return fallback;
  const number = Number(value);
  if (!Number.isFinite(number) || number < min || number > max) {
    throw new Error(`${name} ungueltig: "${value}" (erlaubt: Zahl von ${min} bis ${max})`);
  }
  return number;
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
