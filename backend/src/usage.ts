import { appendFile, mkdir, readdir, readFile, unlink } from "node:fs/promises";
import path from "node:path";
import { addDays, localDate } from "./plan/calendar";

/**
 * Nutzung des Servers: jede Plan-Anfrage mit Ergebnis, Modell, Token, Dauer und geschaetzten Kosten. Eine Zeile JSON pro
 * Anfrage in `metrics/usage-YYYY-MM-DD.jsonl` im Datenverzeichnis (Tag in der Zeitzone der Planung). Daraus rechnet
 * `summarizeUsage` die Tageszahlen fuer `GET /v1/admin/usage`, und der `Alerter` schlaegt Alarm.
 */
export type UsageOutcome = "claude" | "cache" | "fallback" | "failed";

export interface UsageEvent {
  /** ISO-Zeitpunkt. */
  at: string;
  user: string;
  /** day, week, macro, revise, review, race */
  kind: string;
  outcome: UsageOutcome;
  /** Ausfallgrund bei `fallback` und `failed`. */
  reason?: string;
  model?: string;
  inputTokens?: number;
  outputTokens?: number;
  latencyMs?: number;
  costUsd?: number;
}

export type UsageInput = Omit<UsageEvent, "at" | "costUsd">;

export interface UsageRecorder {
  record(event: UsageInput): void;
}

export const noUsage: UsageRecorder = { record: () => {} };

/** Preise in US-Dollar pro Million Token (Eingabe, Ausgabe), nach Modellpraefix. */
const PRICES: Array<{ prefix: string; input: number; output: number }> = [
  { prefix: "claude-opus", input: 4, output: 20 },
  { prefix: "claude-sonnet", input: 2, output: 10 },
  { prefix: "claude-haiku", input: 1, output: 5 }
];
/** Unbekanntes Modell: vorsichtig wie Opus geschaetzt, damit der Kostenalarm eher zu frueh kommt als zu spaet. */
const FALLBACK_PRICE = { input: 4, output: 20 };

export function estimateCostUsd(model: string | undefined, inputTokens = 0, outputTokens = 0): number {
  const price = PRICES.find((entry) => model?.startsWith(entry.prefix)) ?? FALLBACK_PRICE;
  return (inputTokens * price.input + outputTokens * price.output) / 1_000_000;
}

export function withCost(event: UsageInput, at: Date): UsageEvent {
  const tokens = (event.inputTokens ?? 0) + (event.outputTokens ?? 0);
  return {
    at: at.toISOString(),
    ...event,
    ...(tokens > 0 ? { costUsd: round(estimateCostUsd(event.model, event.inputTokens, event.outputTokens), 6) } : {})
  };
}

// MARK: - Datei

export const USAGE_DIR = "metrics";
const FILE_PATTERN = /^usage-(\d{4}-\d{2}-\d{2})\.jsonl$/;

export interface UsageLogOptions {
  dataDir: string;
  timezone: string;
  /** So viele Tage bleiben die Dateien liegen. */
  keepDays?: number;
  now?: () => Date;
  onError?: (error: unknown) => void;
  /** Bekommt jedes Ereignis nach dem Schreiben (Alarme). */
  listeners?: Array<(event: UsageEvent) => void>;
}

export class FileUsageLog implements UsageRecorder {
  private readonly dir: string;
  private readonly now: () => Date;
  private readonly keepDays: number;
  private prunedOn = "";
  /** Schreibvorgaenge nacheinander, damit Zeilen nicht verschraenkt werden. */
  private queue: Promise<void> = Promise.resolve();

  constructor(private readonly options: UsageLogOptions) {
    this.dir = path.join(options.dataDir, USAGE_DIR);
    this.now = options.now ?? (() => new Date());
    this.keepDays = options.keepDays ?? 120;
  }

  record(input: UsageInput): void {
    const at = this.now();
    const event = withCost(input, at);
    const day = localDate(at, this.options.timezone);
    this.queue = this.queue
      .then(async () => {
        await mkdir(this.dir, { recursive: true });
        await appendFile(path.join(this.dir, `usage-${day}.jsonl`), `${JSON.stringify(event)}\n`, "utf8");
        if (this.prunedOn !== day) {
          this.prunedOn = day;
          await this.prune(day);
        }
      })
      .catch((error) => this.options.onError?.(error));
    for (const listener of this.options.listeners ?? []) {
      try {
        listener(event);
      } catch (error) {
        this.options.onError?.(error);
      }
    }
  }

  /** Wartet, bis alles geschrieben ist (Tests, Herunterfahren). */
  async flush(): Promise<void> {
    await this.queue;
  }

  /** Die Ereignisse der letzten `days` Tage bis heute, aeltestes zuerst. */
  async events(days: number): Promise<UsageEvent[]> {
    const today = localDate(this.now(), this.options.timezone);
    const oldest = addDays(today, -(days - 1));
    let names: string[];
    try {
      names = await readdir(this.dir);
    } catch {
      return [];
    }
    const files = names
      .map((name) => FILE_PATTERN.exec(name))
      .filter((match): match is RegExpExecArray => match !== null && match[1] >= oldest && match[1] <= today)
      .sort((a, b) => a[1].localeCompare(b[1]));
    const events: UsageEvent[] = [];
    for (const match of files) {
      const content = await readFile(path.join(this.dir, match[0]), "utf8").catch(() => "");
      for (const line of content.split("\n")) {
        if (line.trim() === "") continue;
        try {
          events.push(JSON.parse(line) as UsageEvent);
        } catch {
          // Eine angefangene Zeile (Absturz beim Schreiben) zaehlt nicht.
        }
      }
    }
    return events;
  }

  private async prune(today: string): Promise<void> {
    const limit = addDays(today, -this.keepDays);
    const names = await readdir(this.dir).catch(() => [] as string[]);
    for (const name of names) {
      const match = FILE_PATTERN.exec(name);
      if (match !== null && match[1] < limit) await unlink(path.join(this.dir, name)).catch(() => {});
    }
  }
}

// MARK: - Auswertung

export interface UsageDay {
  date: string;
  /** Anfragen insgesamt (auch aus dem Cache). */
  requests: number;
  /** Claude-Aufrufe (erfolgreich oder fehlgeschlagen; Cache und Budget-Fallback rufen Claude nicht auf). */
  generations: number;
  outcomes: Record<UsageOutcome, number>;
  /** Anteil der Anfragen, die keinen frischen oder gespeicherten Plan bekamen (`failed`) oder auf den Fallback fielen. */
  failureRate: number;
  reasons: Record<string, number>;
  inputTokens: number;
  outputTokens: number;
  costUsd: number;
  /** Dauer der Claude-Aufrufe je Plan-Art in Sekunden (Median und 95. Perzentil). */
  latency: Record<string, { p50: number; p95: number; count: number }>;
  users: Record<string, { requests: number; costUsd: number }>;
}

export interface UsageSummary {
  days: UsageDay[];
  total: { requests: number; generations: number; costUsd: number; failureRate: number };
}

export function summarizeUsage(events: UsageEvent[], timezone: string, dates: string[]): UsageSummary {
  const byDate = new Map<string, UsageEvent[]>(dates.map((date) => [date, []]));
  for (const event of events) {
    const date = localDate(new Date(event.at), timezone);
    byDate.get(date)?.push(event);
  }
  const days = dates.map((date) => summarizeDay(date, byDate.get(date) ?? []));
  const requests = sum(days.map((day) => day.requests));
  const failed = sum(days.map((day) => day.outcomes.failed + day.outcomes.fallback));
  return {
    days,
    total: {
      requests,
      generations: sum(days.map((day) => day.generations)),
      costUsd: round(sum(days.map((day) => day.costUsd)), 4),
      failureRate: requests === 0 ? 0 : round(failed / requests, 3)
    }
  };
}

function summarizeDay(date: string, events: UsageEvent[]): UsageDay {
  const outcomes: Record<UsageOutcome, number> = { claude: 0, cache: 0, fallback: 0, failed: 0 };
  const reasons: Record<string, number> = {};
  const latencies: Record<string, number[]> = {};
  const users: Record<string, { requests: number; costUsd: number }> = {};
  let inputTokens = 0;
  let outputTokens = 0;
  let cost = 0;
  let generations = 0;
  for (const event of events) {
    outcomes[event.outcome] = (outcomes[event.outcome] ?? 0) + 1;
    if (event.reason !== undefined) reasons[event.reason] = (reasons[event.reason] ?? 0) + 1;
    if (event.latencyMs !== undefined) {
      generations += 1;
      (latencies[event.kind] ??= []).push(event.latencyMs);
    }
    inputTokens += event.inputTokens ?? 0;
    outputTokens += event.outputTokens ?? 0;
    cost += event.costUsd ?? 0;
    const user = (users[event.user] ??= { requests: 0, costUsd: 0 });
    user.requests += 1;
    user.costUsd = round(user.costUsd + (event.costUsd ?? 0), 4);
  }
  const latency = Object.fromEntries(
    Object.entries(latencies).map(([kind, values]) => [kind, { p50: percentile(values, 0.5), p95: percentile(values, 0.95), count: values.length }])
  );
  return {
    date,
    requests: events.length,
    generations,
    outcomes,
    failureRate: events.length === 0 ? 0 : round((outcomes.failed + outcomes.fallback) / events.length, 3),
    reasons,
    inputTokens,
    outputTokens,
    costUsd: round(cost, 4),
    latency,
    users
  };
}

/** Naechster-Rang-Perzentil in Sekunden, eine Nachkommastelle. */
function percentile(values: number[], p: number): number {
  const sorted = [...values].sort((a, b) => a - b);
  const index = Math.min(sorted.length - 1, Math.max(0, Math.ceil(p * sorted.length) - 1));
  return round(sorted[index] / 1000, 1);
}

function sum(values: number[]): number {
  return values.reduce((total, value) => total + value, 0);
}

function round(value: number, digits: number): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

/** Die letzten `days` Kalendertage bis `today`, aeltester zuerst. */
export function lastDays(today: string, days: number): string[] {
  return Array.from({ length: days }, (_, index) => addDays(today, index - (days - 1)));
}
