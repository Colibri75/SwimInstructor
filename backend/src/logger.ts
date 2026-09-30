import pino, { DestinationStream, Logger } from "pino";
import { Config } from "./config";

/**
 * Strukturiertes JSON-Logging (landet bei systemd im Journal). Der Authorization-Header wird
 * nie geloggt, damit der API-Token nicht in Logdateien auftaucht.
 */
export function createLogger(config: Config, destination?: DestinationStream): Logger {
  return pino(
    {
      level: config.logLevel,
      redact: {
        paths: ["req.headers.authorization", 'req.headers["x-api-key"]'],
        censor: "[redacted]"
      }
    },
    destination
  );
}
