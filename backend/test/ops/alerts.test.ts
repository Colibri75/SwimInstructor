import { Alerter, webhookNotifier } from "../../src/alerts";
import { UsageEvent } from "../../src/usage";

const TZ = "Europe/Berlin";

function setup(start = "2026-10-05T08:00:00Z") {
  let now = new Date(start).getTime();
  const sent: Array<{ title: string; message: string }> = [];
  const alerter = new Alerter(
    async (title, message) => {
      sent.push({ title, message });
    },
    { dailyCostUsd: 1, failuresPerHour: 3, failureRate: 0.5, timezone: TZ, now: () => new Date(now) }
  );
  const at = () => new Date(now).toISOString();
  const observe = (partial: Partial<UsageEvent>) => alerter.observe({ at: at(), user: "owner", kind: "day", outcome: "claude", ...partial });
  return { alerter, sent, observe, advance: (ms: number) => (now += ms) };
}

const MINUTE = 60_000;

describe("Alarme", () => {
  it("meldet die Tageskosten einmal am Tag", () => {
    const { sent, observe, advance } = setup();
    observe({ costUsd: 0.6 });
    expect(sent).toHaveLength(0);
    observe({ costUsd: 0.6 });
    observe({ costUsd: 0.6 });
    expect(sent.map((s) => s.title)).toEqual(["Peaksmith: Tageskosten"]);
    expect(sent[0].message).toContain("$1.20");

    advance(24 * 60 * MINUTE);
    observe({ costUsd: 0.5 });
    expect(sent).toHaveLength(1);
    observe({ costUsd: 0.6 });
    expect(sent).toHaveLength(2);
  });

  it("zaehlt die Kosten von vor dem Start mit", () => {
    const { alerter, sent, observe } = setup();
    alerter.seed([
      { at: "2026-10-05T06:00:00Z", user: "owner", kind: "macro", outcome: "claude", costUsd: 0.9 },
      { at: "2026-10-04T06:00:00Z", user: "owner", kind: "macro", outcome: "claude", costUsd: 5 }
    ]);
    observe({ costUsd: 0.2 });
    expect(sent).toHaveLength(1);
  });

  it("meldet viele Ausfaelle in der letzten Stunde, dann drei Stunden Ruhe", () => {
    const { sent, observe, advance } = setup();
    observe({ outcome: "failed", reason: "timeout" });
    observe({ outcome: "claude" });
    observe({ outcome: "fallback", reason: "timeout" });
    expect(sent).toHaveLength(0);
    observe({ outcome: "failed", reason: "upstream_error" });
    expect(sent.map((s) => s.title)).toEqual(["Peaksmith: Pläne fallen aus"]);
    expect(sent[0].message).toContain("3 von 4");
    expect(sent[0].message).toContain("timeout 2×");

    advance(30 * MINUTE);
    observe({ outcome: "failed", reason: "timeout" });
    expect(sent).toHaveLength(1);

    advance(3 * 60 * MINUTE);
    observe({ outcome: "failed", reason: "timeout" });
    observe({ outcome: "failed", reason: "timeout" });
    observe({ outcome: "failed", reason: "timeout" });
    expect(sent).toHaveLength(2);
  });

  it("vergisst Ausfaelle nach einer Stunde", () => {
    const { sent, observe, advance } = setup();
    observe({ outcome: "failed", reason: "timeout" });
    observe({ outcome: "failed", reason: "timeout" });
    advance(61 * MINUTE);
    observe({ outcome: "failed", reason: "timeout" });
    expect(sent).toHaveLength(0);
  });

  it("meldet Konfigurationsfehler sofort und ein erschoepftes Budget einmal je Nutzer und Tag", () => {
    const { sent, observe } = setup();
    observe({ outcome: "failed", reason: "auth" });
    observe({ outcome: "failed", reason: "budget_exceeded", user: "anna", kind: "macro" });
    observe({ outcome: "fallback", reason: "budget_exceeded", user: "anna" });

    expect(sent.map((s) => s.title)).toEqual(["Peaksmith: Konfigurationsfehler", "Peaksmith: Budget erschöpft"]);
    expect(sent[1].message).toContain('"anna"');
  });
});

describe("Alarme: Webhook", () => {
  function fakeFetch(status = 200) {
    return jest.fn().mockResolvedValue({ ok: status < 400, status });
  }

  it.each([
    [
      "ntfy",
      (init: RequestInit) => {
        expect(init.body).toBe("Text");
        expect((init.headers as Record<string, string>).Title).toBe("Peaksmith: Budget erschoepft");
      }
    ],
    ["slack", (init: RequestInit) => expect(JSON.parse(String(init.body))).toEqual({ text: "*Peaksmith: Budget erschöpft*\nText" })],
    ["discord", (init: RequestInit) => expect(JSON.parse(String(init.body))).toEqual({ content: "**Peaksmith: Budget erschöpft**\nText" })],
    ["json", (init: RequestInit) => expect(JSON.parse(String(init.body))).toEqual({ title: "Peaksmith: Budget erschöpft", message: "Text" })]
  ] as const)("schickt im Format %s", async (format, check) => {
    const fetchImpl = fakeFetch();
    await webhookNotifier("https://example.test/hook", format, fetchImpl as unknown as typeof fetch)("Peaksmith: Budget erschöpft", "Text");

    expect(fetchImpl).toHaveBeenCalledTimes(1);
    const [url, init] = fetchImpl.mock.calls[0] as [string, RequestInit];
    expect(url).toBe("https://example.test/hook");
    expect(init.method).toBe("POST");
    check(init);
  });

  it("meldet eine Fehlantwort als Fehler", async () => {
    await expect(webhookNotifier("https://example.test/hook", "json", fakeFetch(500) as unknown as typeof fetch)("T", "M")).rejects.toThrow("500");
  });
});
