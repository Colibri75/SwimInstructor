import { mkdtempSync, readdirSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { estimateCostUsd, FileUsageLog, lastDays, summarizeUsage, UsageEvent, withCost } from "../../src/usage";

const TZ = "Europe/Berlin";

function event(partial: Partial<UsageEvent>): UsageEvent {
  return { at: "2026-10-05T10:00:00.000Z", user: "owner", kind: "day", outcome: "claude", ...partial };
}

describe("Nutzung: Kosten", () => {
  it("schaetzt nach Modellpraefix, unbekannte Modelle wie Opus", () => {
    expect(estimateCostUsd("claude-opus-5-5", 10_000, 2_000)).toBeCloseTo(0.08);
    expect(estimateCostUsd("claude-sonnet-5-5", 10_000, 2_000)).toBeCloseTo(0.04);
    expect(estimateCostUsd("claude-haiku-4-5-20251001", 10_000, 2_000)).toBeCloseTo(0.02);
    expect(estimateCostUsd("ein-anderes-modell", 10_000, 2_000)).toBeCloseTo(0.08);
  });

  it("setzt Kosten nur, wenn Token verbraucht wurden", () => {
    const at = new Date("2026-10-05T10:00:00Z");
    expect(withCost({ user: "owner", kind: "day", outcome: "cache" }, at)).toEqual({ at: at.toISOString(), user: "owner", kind: "day", outcome: "cache" });
    expect(withCost({ user: "owner", kind: "day", outcome: "claude", model: "claude-opus-5-5", inputTokens: 1_000_000, outputTokens: 0 }, at).costUsd).toBe(4);
  });
});

describe("Nutzung: Datei", () => {
  it("schreibt eine Zeile je Ereignis in die Datei des Tages (Zeitzone der Planung) und liest sie zurueck", async () => {
    const dataDir = mkdtempSync(path.join(tmpdir(), "usage-"));
    let now = new Date("2026-10-04T22:30:00Z"); // in Berlin schon der 5.10. (00:30 Uhr)
    const seen: UsageEvent[] = [];
    const log = new FileUsageLog({ dataDir, timezone: TZ, now: () => now, listeners: [(e) => seen.push(e)] });

    log.record({ user: "owner", kind: "day", outcome: "claude", model: "claude-opus-5-5", inputTokens: 9_000, outputTokens: 2_000, latencyMs: 25_000 });
    now = new Date("2026-10-05T08:00:00Z");
    log.record({ user: "anna", kind: "week", outcome: "failed", reason: "timeout", latencyMs: 75_000 });
    await log.flush();

    expect(readdirSync(path.join(dataDir, "metrics"))).toEqual(["usage-2026-10-05.jsonl"]);
    const lines = readFileSync(path.join(dataDir, "metrics", "usage-2026-10-05.jsonl"), "utf8").trim().split("\n");
    expect(lines).toHaveLength(2);
    expect(seen.map((e) => e.user)).toEqual(["owner", "anna"]);
    expect(seen[0].costUsd).toBeCloseTo(0.076);

    const events = await log.events(1);
    expect(events.map((e) => e.kind)).toEqual(["day", "week"]);
  });

  it("ueberspringt kaputte Zeilen und loescht alte Dateien", async () => {
    const dataDir = mkdtempSync(path.join(tmpdir(), "usage-"));
    const dir = path.join(dataDir, "metrics");
    mkdirSync(dir, { recursive: true });
    writeFileSync(path.join(dir, "usage-2026-01-01.jsonl"), `${JSON.stringify(event({ at: "2026-01-01T10:00:00Z" }))}\n`);
    writeFileSync(path.join(dir, "usage-2026-10-04.jsonl"), `${JSON.stringify(event({ at: "2026-10-04T10:00:00Z" }))}\n{"angefangen`);
    const log = new FileUsageLog({ dataDir, timezone: TZ, keepDays: 30, now: () => new Date("2026-10-05T10:00:00Z") });

    expect((await log.events(2)).map((e) => e.at)).toEqual(["2026-10-04T10:00:00Z"]);
    log.record({ user: "owner", kind: "day", outcome: "cache" });
    await log.flush();

    expect(readdirSync(dir).sort()).toEqual(["usage-2026-10-04.jsonl", "usage-2026-10-05.jsonl"]);
  });

  it("liefert ohne Ordner keine Ereignisse", async () => {
    const log = new FileUsageLog({ dataDir: path.join(tmpdir(), "gibt-es-nicht-usage"), timezone: TZ });
    expect(await log.events(7)).toEqual([]);
  });
});

describe("Nutzung: Auswertung", () => {
  it("zaehlt je Tag Ergebnisse, Gruende, Kosten, Dauer und Nutzer", () => {
    const events: UsageEvent[] = [
      event({ outcome: "claude", latencyMs: 20_000, inputTokens: 9_000, outputTokens: 2_000, costUsd: 0.076, model: "claude-opus-5-5" }),
      event({ outcome: "claude", latencyMs: 40_000, costUsd: 0.1, user: "anna" }),
      event({ outcome: "cache" }),
      event({ outcome: "fallback", reason: "timeout", latencyMs: 75_000 }),
      event({ kind: "macro", outcome: "failed", reason: "budget_exceeded", user: "anna" }),
      event({ at: "2026-10-03T10:00:00Z", kind: "macro", outcome: "claude", latencyMs: 100_000, costUsd: 0.25 })
    ];

    const summary = summarizeUsage(events, TZ, lastDays("2026-10-05", 3));

    expect(summary.days.map((d) => d.date)).toEqual(["2026-10-03", "2026-10-04", "2026-10-05"]);
    const today = summary.days[2];
    expect(today.requests).toBe(5);
    expect(today.generations).toBe(3);
    expect(today.outcomes).toEqual({ claude: 2, cache: 1, fallback: 1, failed: 1 });
    expect(today.failureRate).toBe(0.4);
    expect(today.reasons).toEqual({ timeout: 1, budget_exceeded: 1 });
    expect(today.costUsd).toBeCloseTo(0.176);
    expect(today.latency.day).toEqual({ p50: 40, p95: 75, count: 3 });
    expect(today.users).toEqual({ owner: { requests: 3, costUsd: 0.076 }, anna: { requests: 2, costUsd: 0.1 } });
    expect(summary.days[1].requests).toBe(0);
    expect(summary.total).toEqual({ requests: 6, generations: 4, costUsd: 0.426, failureRate: 0.333 });
  });
});
