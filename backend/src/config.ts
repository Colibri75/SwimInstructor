export type Environment = "development" | "production" | "test";

export interface Config {
  env: Environment;
  host: string;
  port: number;
  apiToken: string;
  logLevel: string;
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
    logLevel: env.LOG_LEVEL?.trim() || (environment === "test" ? "silent" : "info")
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
