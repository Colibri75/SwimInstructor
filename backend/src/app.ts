import express, { ErrorRequestHandler, Express, Router } from "express";
import { Logger } from "pino";
import { pinoHttp } from "pino-http";
import { currentUser, requireBearerToken } from "./auth";
import { Config } from "./config";
import { SingleUserDirectory, UserDirectory } from "./users";

export interface AppOptions {
  /** Haengt Routen unter /v1 ein (bereits hinter der Token-Pruefung, der Nutzer steht in `res.locals.user`). */
  registerV1Routes?: (router: Router) => void;
  /** Die Nutzer des Servers; ohne Angabe nur der Token aus `API_TOKEN`. */
  users?: UserDirectory;
}

const MAX_BODY_SIZE = "100kb";

export function createApp(config: Config, logger: Logger, options: AppOptions = {}): Express {
  const app = express();
  app.disable("x-powered-by");
  // Der Server laeuft hinter nginx auf demselben Host: nur dessen X-Forwarded-* vertrauen.
  app.set("trust proxy", "loopback");

  app.use(
    pinoHttp({
      logger,
      // Health-Checks (Uptime-Monitor alle paar Sekunden) wuerden das Log sonst zumuellen.
      autoLogging: { ignore: (req) => req.url === "/health" },
      // Wer die Anfrage gestellt hat (Kennung, nie der Token).
      customProps: (_req, res) => {
        const user = currentUser((res as unknown as { locals?: Record<string, unknown> }).locals ?? {});
        return user ? { user: user.id } : {};
      },
      customLogLevel: (_req, res, error) => {
        if (error || res.statusCode >= 500) return "error";
        if (res.statusCode >= 400) return "warn";
        return "info";
      }
    })
  );

  // Oeffentlich und ohne Daten: nur "lebt der Server". Dient Monitoring und Deploy-Check.
  app.get("/health", (_req, res) => {
    res.json({ status: "ok", uptimeSeconds: Math.round(process.uptime()) });
  });

  const v1 = Router();
  // Erst Auth, dann Body-Parsing: Unautorisierte Requests kosten keine Parsing-Arbeit.
  v1.use(requireBearerToken(options.users ?? new SingleUserDirectory(config.apiToken)));
  v1.use(express.json({ limit: MAX_BODY_SIZE }));
  v1.get("/status", (_req, res) => {
    res.json({ status: "authenticated", user: currentUser(res.locals)?.id });
  });
  options.registerV1Routes?.(v1);
  app.use("/v1", v1);

  app.use((_req, res) => {
    res.status(404).json({ error: "not_found" });
  });
  app.use(errorHandler);

  return app;
}

const errorHandler: ErrorRequestHandler = (error, req, res, _next) => {
  const status = clientErrorStatus(error) ?? 500;
  if (status >= 500) {
    req.log.error({ err: error }, "unhandled error");
    res.status(500).json({ error: "internal_error" });
    return;
  }
  // 4xx aus Express/body-parser (kaputtes JSON, zu grosser Body): Detail nicht nach aussen geben.
  res.status(status).json({ error: status === 413 ? "payload_too_large" : "bad_request" });
};

function clientErrorStatus(error: unknown): number | undefined {
  const status = (error as { status?: unknown } | null)?.status;
  return typeof status === "number" && status >= 400 && status < 500 ? status : undefined;
}
