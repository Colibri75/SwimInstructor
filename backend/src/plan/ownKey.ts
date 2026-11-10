import { AsyncLocalStorage } from "node:async_hooks";
import { RequestHandler } from "express";

/**
 * Eigener Claude-Schluessel eines Nutzers. Standard ist der Schluessel des Servers (`ANTHROPIC_API_KEY`, nur in der
 * Server-Konfiguration, nie in einer Antwort, im Log oder in der App). Wer selbst zahlen will, traegt in der App einen
 * eigenen Schluessel ein; die App schickt ihn bei jeder Anfrage in diesem Header. Der Server speichert ihn nie und
 * nutzt ihn nur fuer die Claude-Aufrufe dieser einen Anfrage, ohne die Kostenbremse des Servers.
 */
export const OWN_KEY_HEADER = "x-anthropic-api-key";

/** Anthropic-Schluessel beginnen mit "sk-ant-"; alles andere ist ein Tippfehler. */
const KEY_PATTERN = /^sk-ant-[A-Za-z0-9_-]{20,300}$/;

export function isPlausibleOwnKey(value: string): boolean {
  return KEY_PATTERN.test(value);
}

const storage = new AsyncLocalStorage<string>();

/** Der eigene Schluessel der laufenden Anfrage, sonst `undefined`. */
export function currentOwnKey(): string | undefined {
  return storage.getStore();
}

/** Fuehrt `work` mit diesem eigenen Schluessel aus (fuer Tests und die Middleware). */
export function withOwnKey<T>(key: string, work: () => T): T {
  return storage.run(key, work);
}

/**
 * Liest den Header und haengt den Schluessel an die Anfrage. Leer oder fehlend: Server-Schluessel. Ein Wert, der kein
 * Anthropic-Schluessel sein kann, ergibt 400, statt still auf Kosten des Servers zu planen.
 */
export const ownKeyMiddleware: RequestHandler = (req, res, next) => {
  const raw = req.headers[OWN_KEY_HEADER];
  const value = (Array.isArray(raw) ? raw[0] : raw)?.trim() ?? "";
  if (value === "") {
    next();
    return;
  }
  if (!isPlausibleOwnKey(value)) {
    res.status(400).json({ error: "invalid_own_key" });
    return;
  }
  storage.run(value, () => next());
};
