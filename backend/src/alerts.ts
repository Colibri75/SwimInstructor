import { AlertFormat } from "./config";
import { localDate } from "./plan/calendar";
import { UsageEvent } from "./usage";

/**
 * Alarme aus der Nutzung: Tageskosten ueber der Schwelle, viele Ausfaelle in der letzten Stunde, Konfigurationsfehler
 * (Key ungueltig, Anfrage abgelehnt), erschoepftes Budget. Jeder Alarm hat eine Ruhezeit, damit ein Ausfall nicht im
 * Minutentakt meldet. Verschickt wird per Webhook (ntfy, Slack, Discord oder ein JSON-Empfaenger).
 */

export interface AlertOptions {
  /** Ab diesen Kosten am Tag (US-Dollar) einmal am Tag melden. */
  dailyCostUsd: number;
  /** Ab so vielen Ausfaellen in der letzten Stunde ... */
  failuresPerHour: number;
  /** ... und diesem Anteil an allen Anfragen der Stunde melden. */
  failureRate: number;
  timezone: string;
  now?: () => Date;
}

export type Notify = (title: string, message: string) => Promise<void>;

const HOUR_MS = 60 * 60 * 1000;
/** Ausfallgruende, die nicht von Claude kommen, sondern von der Konfiguration: sofort melden. */
const CONFIG_REASONS = new Set(["auth", "bad_request", "not_configured"]);

export class Alerter {
  private readonly now: () => Date;
  private recent: UsageEvent[] = [];
  private costDay = "";
  private costToday = 0;
  private readonly lastSent = new Map<string, number>();

  constructor(
    private readonly notify: Notify,
    private readonly options: AlertOptions,
    private readonly onError: (error: unknown) => void = () => {}
  ) {
    this.now = options.now ?? (() => new Date());
  }

  /** Kosten von heute, die vor dem Start schon anfielen (aus der Nutzungsdatei). */
  seed(events: UsageEvent[]): void {
    const today = localDate(this.now(), this.options.timezone);
    this.costDay = today;
    this.costToday = events.filter((event) => localDate(new Date(event.at), this.options.timezone) === today).reduce((sum, event) => sum + (event.costUsd ?? 0), 0);
  }

  observe(event: UsageEvent): void {
    const now = this.now().getTime();
    const today = localDate(this.now(), this.options.timezone);
    if (today !== this.costDay) {
      this.costDay = today;
      this.costToday = 0;
    }
    this.costToday += event.costUsd ?? 0;
    this.recent = [...this.recent.filter((entry) => Date.parse(entry.at) > now - HOUR_MS), event];

    if (this.costToday >= this.options.dailyCostUsd) {
      this.send(`cost:${today}`, Infinity, "Peaksmith: Tageskosten", `Heute schon $${this.costToday.toFixed(2)} für Pläne (Schwelle $${this.options.dailyCostUsd.toFixed(2)}).`);
    }

    // Budget und Konfiguration haben eigene Alarme; hier zaehlen nur Ausfaelle von Claude und der Sicherheitsschicht.
    const failures = this.recent.filter(
      (entry) => (entry.outcome === "failed" || entry.outcome === "fallback") && !CONFIG_REASONS.has(entry.reason ?? "") && entry.reason !== "budget_exceeded"
    );
    const rate = failures.length / this.recent.length;
    if (failures.length >= this.options.failuresPerHour && rate >= this.options.failureRate) {
      const reasons = countReasons(failures);
      this.send("failures", 3 * HOUR_MS, "Peaksmith: Pläne fallen aus", `${failures.length} von ${this.recent.length} Anfragen der letzten Stunde ohne frischen Plan (${reasons}).`);
    }

    if ((event.outcome === "failed" || event.outcome === "fallback") && event.reason !== undefined) {
      if (CONFIG_REASONS.has(event.reason)) {
        this.send(`config:${event.reason}`, 6 * HOUR_MS, "Peaksmith: Konfigurationsfehler", `Plan-Anfrage scheiterte mit "${event.reason}". Bitte ANTHROPIC_API_KEY und Server-Log prüfen.`);
      }
      if (event.reason === "budget_exceeded") {
        this.send(`budget:${event.user}:${today}`, Infinity, "Peaksmith: Budget erschöpft", `Nutzer "${event.user}" hat das Aufrufbudget erreicht; es gibt bis auf Weiteres nur gespeicherte Pläne.`);
      }
    }
  }

  /** Einmal je Schluessel und Ruhezeit (`Infinity`: einmal je Schluessel, etwa je Tag). */
  private send(key: string, quietMs: number, title: string, message: string): void {
    const now = this.now().getTime();
    const last = this.lastSent.get(key);
    if (last !== undefined && (quietMs === Infinity || now - last < quietMs)) return;
    this.lastSent.set(key, now);
    this.notify(title, message).catch((error) => this.onError(error));
  }
}

function countReasons(events: UsageEvent[]): string {
  const counts = new Map<string, number>();
  for (const event of events) counts.set(event.reason ?? "unbekannt", (counts.get(event.reason ?? "unbekannt") ?? 0) + 1);
  return [...counts.entries()].map(([reason, count]) => `${reason} ${count}×`).join(", ");
}

/** Verschickt einen Alarm an einen Webhook. Fehler wirft er weiter (der Alerter loggt sie). */
export function webhookNotifier(url: string, format: AlertFormat, fetchImpl: typeof fetch = fetch): Notify {
  return async (title, message) => {
    let init: RequestInit;
    switch (format) {
      case "ntfy":
        // ntfy: Text im Body, Titel als Header (nur ASCII erlaubt, daher ohne Umlaute im Titel).
        init = { method: "POST", headers: { Title: asciiOnly(title), Tags: "warning" }, body: message };
        break;
      case "slack":
        init = { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ text: `*${title}*\n${message}` }) };
        break;
      case "discord":
        init = { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ content: `**${title}**\n${message}` }) };
        break;
      case "json":
        init = { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ title, message }) };
        break;
    }
    const response = await fetchImpl(url, { ...init, signal: AbortSignal.timeout(10_000) });
    if (!response.ok) throw new Error(`Alarm-Webhook antwortete mit ${response.status}`);
  };
}

function asciiOnly(value: string): string {
  return value.replace(/ä/g, "ae").replace(/ö/g, "oe").replace(/ü/g, "ue").replace(/ß/g, "ss").replace(/[^\x20-\x7e]/g, "");
}
