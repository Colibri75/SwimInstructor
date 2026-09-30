import { Writable } from "node:stream";
import { Express, Router } from "express";
import { AppOptions, createApp } from "../src/app";
import { Config } from "../src/config";
import { createLogger } from "../src/logger";

export const TEST_TOKEN = "test-token-0123456789abcdef0123456789abcdef";

export const testConfig: Config = {
  env: "test",
  host: "127.0.0.1",
  port: 0,
  apiToken: TEST_TOKEN,
  logLevel: "silent"
};

export function buildApp(options: AppOptions = {}): Express {
  return createApp(testConfig, createLogger(testConfig), options);
}

export interface LogRecord {
  level: number;
  msg?: string;
  [key: string]: unknown;
}

/** App mit echtem Logger, dessen JSON-Zeilen im Speicher landen (fuer die Logging-Tests). */
export function buildAppWithCapturedLogs(options: AppOptions = {}): {
  app: Express;
  records: () => LogRecord[];
  raw: () => string;
} {
  const chunks: string[] = [];
  const stream = new Writable({
    write(chunk, _encoding, callback) {
      chunks.push(chunk.toString());
      callback();
    }
  });
  const logger = createLogger({ ...testConfig, logLevel: "info" }, stream);
  const raw = () => chunks.join("");
  const records = () =>
    raw()
      .split("\n")
      .filter((line) => line.trim() !== "")
      .map((line) => JSON.parse(line) as LogRecord);
  return { app: createApp(testConfig, logger, options), records, raw };
}

export function throwingRoute(router: Router): void {
  router.get("/boom", () => {
    throw new Error("kaputt: geheime interne Details");
  });
}
