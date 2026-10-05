import Anthropic from "@anthropic-ai/sdk";
import path from "node:path";
import { adminRoutes } from "./admin";
import { Alerter, webhookNotifier } from "./alerts";
import { createApp } from "./app";
import { loadConfig, Config } from "./config";
import { createLogger } from "./logger";
import { GenerationBudget, UserBudgets } from "./plan/budget";
import { ClaudePlanGenerator } from "./plan/generator";
import { multiRoutes } from "./plan/multi/routes";
import { MultiPlanService } from "./plan/multi/service";
import { DayPlanStoreV2, FileDayPlanStoreV2 } from "./plan/multi/store";
import { FileUsageLog, UsageEvent } from "./usage";
import { FileUserDirectory, userDataDir, USERS_FILE } from "./users";

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
        macroTimeoutMs: config.claudeMacroTimeoutMs,
        serverFallback: config.claudeServerFallback
      });

// Budgets ueber alle Plaene (jeder kostet einen Claude-Aufruf): eines je Nutzer und eines fuer den ganzen Server.
const budget = new GenerationBudget(config.maxGenerationsTotalPerHour, config.maxGenerationsTotalPerDay);
const userBudgets = new UserBudgets(config.maxGenerationsPerHour, config.maxGenerationsPerDay);

// Alarme (optional) bekommen jedes Ereignis der Nutzung.
const listeners: Array<(event: UsageEvent) => void> = [];
let alerter: Alerter | undefined;
if (config.alerts !== undefined) {
  alerter = new Alerter(
    webhookNotifier(config.alerts.webhookUrl, config.alerts.format),
    { ...config.alerts, timezone: config.planTimezone },
    (error) => logger.warn({ err: error }, "alert could not be sent")
  );
  listeners.push((event) => alerter?.observe(event));
}
const usage = new FileUsageLog({
  dataDir: config.dataDir,
  timezone: config.planTimezone,
  listeners,
  onError: (error) => logger.warn({ err: error }, "usage could not be recorded")
});
if (alerter !== undefined) {
  const seeded = alerter;
  usage.events(1).then((events) => seeded.seed(events)).catch(() => {});
}

// Ein Speicher je Nutzer, angelegt beim ersten Zugriff.
const stores = new Map<string, DayPlanStoreV2>();
const storeFor = (user: string): DayPlanStoreV2 => {
  let store = stores.get(user);
  if (store === undefined) {
    store = new FileDayPlanStoreV2(userDataDir(config.dataDir, user));
    stores.set(user, store);
  }
  return store;
};

const planService = new MultiPlanService({
  generator,
  store: storeFor,
  budget,
  userBudgets,
  usage,
  logger,
  timezone: config.planTimezone
});

const users = new FileUserDirectory(config.apiToken, config.dataDir, (message) => logger.error(message));
const registerPlanRoutes = multiRoutes(planService);
const registerAdminRoutes = adminRoutes({ usage, usersFile: path.join(config.dataDir, USERS_FILE), timezone: config.planTimezone });
const app = createApp(config, logger, {
  users,
  registerV1Routes: (router) => {
    registerPlanRoutes(router);
    registerAdminRoutes(router);
  }
});

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
