import request from "supertest";
import { buildApp, buildAppWithCapturedLogs, throwingRoute, TEST_TOKEN } from "./helpers";

const auth = { Authorization: `Bearer ${TEST_TOKEN}` };

describe("Fehlerbehandlung", () => {
  it("liefert bei einem internen Fehler 500 ohne Stacktrace oder Details", async () => {
    const response = await request(buildApp({ registerV1Routes: throwingRoute })).get("/v1/boom").set(auth);

    expect(response.status).toBe(500);
    expect(response.body).toEqual({ error: "internal_error" });
    expect(JSON.stringify(response.body)).not.toContain("geheime");
  });

  it("liefert bei kaputtem JSON mit gueltigem Token 400", async () => {
    const response = await request(buildApp())
      .post("/v1/status")
      .set(auth)
      .set("Content-Type", "application/json")
      .send("{kaputt");

    expect(response.status).toBe(400);
    expect(response.body).toEqual({ error: "bad_request" });
  });

  it("lehnt zu grosse Bodies mit 413 ab", async () => {
    const response = await request(buildApp())
      .post("/v1/status")
      .set(auth)
      .set("Content-Type", "application/json")
      .send(JSON.stringify({ data: "x".repeat(200_000) }));

    expect(response.status).toBe(413);
    expect(response.body).toEqual({ error: "payload_too_large" });
  });

  it("stuerzt nach einem Fehler nicht ab: der naechste Request geht durch", async () => {
    const app = buildApp({ registerV1Routes: throwingRoute });

    await request(app).get("/v1/boom").set(auth);
    const next = await request(app).get("/health");

    expect(next.status).toBe(200);
  });
});

describe("Logging", () => {
  it("loggt Requests mit Methode, Pfad und Status", async () => {
    const { app, records } = buildAppWithCapturedLogs();

    await request(app).get("/v1/status").set(auth);

    const entry = records().find((record) => record.msg === "request completed");
    expect(entry).toBeDefined();
    expect(entry).toMatchObject({
      level: 30,
      req: { method: "GET", url: "/v1/status" },
      res: { statusCode: 200 }
    });
  });

  it("loggt fehlgeschlagene Auth als Warnung", async () => {
    const { app, records } = buildAppWithCapturedLogs();

    await request(app).get("/v1/status");

    const entry = records().find((record) => record.msg === "request completed");
    expect(entry).toMatchObject({ level: 40, res: { statusCode: 401 } });
  });

  it("loggt interne Fehler als error mit der Fehlermeldung", async () => {
    const { app, records } = buildAppWithCapturedLogs({ registerV1Routes: throwingRoute });

    await request(app).get("/v1/boom").set(auth);

    const entry = records().find((record) => record.msg === "unhandled error");
    expect(entry).toBeDefined();
    expect(entry?.level).toBe(50);
    expect(JSON.stringify(entry)).toContain("kaputt");
  });

  it("schreibt den API-Token niemals ins Log", async () => {
    const { app, raw } = buildAppWithCapturedLogs();

    await request(app).get("/v1/status").set(auth);

    expect(raw()).not.toContain(TEST_TOKEN);
    expect(raw()).toContain("[redacted]");
  });

  it("loggt den Health-Check nicht", async () => {
    const { app, records } = buildAppWithCapturedLogs();

    await request(app).get("/health");

    expect(records().filter((record) => record.msg === "request completed")).toHaveLength(0);
  });
});
