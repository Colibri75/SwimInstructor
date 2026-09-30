import Anthropic from "@anthropic-ai/sdk";
import { createApp } from "./app";
import { loadConfig, Config } from "./config";
import { createLogger } from "./logger";
import { GenerationBudget } from "./plan/budget";
import { ClaudePlanGenerator } from "./plan/generator";
import { planRoutes } from "./plan/routes";
import { PlanService } from "./plan/service";
import { FilePlanStore } from "./plan/store";

let config: Config;
try {
  config = loadConfig();
} catch (error) {
  // Bewusst kein Logger: die Konfiguration (Loglevel) ist ja gerade das, was fehlt.
  console.error(`Konfigurationsfehler: ${(error as Error).message}`);
  process.exit(1);
}

const logger = createLogger(config);

if (config.anthropicApiKey === undefined) {
  logger.warn("ANTHROPIC_API_KEY nicht gesetzt: /v1/plan/today liefert nur gespeicherte Pläne");
}
const generator =
  config.anthropicApiKey === undefined
    ? null
    : new ClaudePlanGenerator(new Anthropic({ apiKey: config.anthropicApiKey }), {
        model: config.claudeModel,
        effort: config.claudeEffort,
        timeoutMs: config.claudeTimeoutMs,
        serverFallback: config.claudeServerFallback
      });

const planService = new PlanService({
  generator,
  store: new FilePlanStore(config.dataDir),
  budget: new GenerationBudget(config.maxGenerationsPerHour, config.maxGenerationsPerDay),
  logger,
  timezone: config.planTimezone
});

const app = createApp(config, logger, { registerV1Routes: planRoutes(planService) });

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
