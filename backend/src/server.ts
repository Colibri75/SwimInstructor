import { createApp } from "./app";
import { loadConfig, Config } from "./config";
import { createLogger } from "./logger";

let config: Config;
try {
  config = loadConfig();
} catch (error) {
  // Bewusst kein Logger: die Konfiguration (Loglevel) ist ja gerade das, was fehlt.
  console.error(`Konfigurationsfehler: ${(error as Error).message}`);
  process.exit(1);
}

const logger = createLogger(config);
const app = createApp(config, logger);

const server = app.listen(config.port, config.host, () => {
  logger.info({ host: config.host, port: config.port, env: config.env }, "server listening");
});

function shutdown(signal: string): void {
  logger.info({ signal }, "shutting down");
  server.close(() => process.exit(0));
  // Haengende Verbindungen nicht ewig abwarten.
  setTimeout(() => process.exit(1), 10_000).unref();
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
