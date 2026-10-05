import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import request from "supertest";
import { adminRoutes } from "../../src/admin";
import { createApp } from "../../src/app";
import { createLogger } from "../../src/logger";
import { FileUsageLog } from "../../src/usage";
import { addUser, FileUserDirectory, USERS_FILE } from "../../src/users";
import { TEST_TOKEN, testConfig } from "../helpers";

function setup() {
  const dataDir = mkdtempSync(path.join(tmpdir(), "admin-"));
  const usersFile = path.join(dataDir, USERS_FILE);
  const anna = addUser(usersFile, "anna", { name: "Anna", now: new Date("2026-10-01T10:00:00Z") });
  const chef = addUser(usersFile, "chef", { admin: true });
  const now = () => new Date("2026-10-05T10:00:00Z");
  const usage = new FileUsageLog({ dataDir, timezone: "Europe/Berlin", now });
  const app = createApp(testConfig, createLogger(testConfig), {
    users: new FileUserDirectory(TEST_TOKEN, dataDir, () => {}, 0),
    registerV1Routes: adminRoutes({ usage, usersFile, timezone: "Europe/Berlin", now })
  });
  return { app, usage, annaToken: anna.token, chefToken: chef.token };
}

describe("Admin-Routen", () => {
  it("zeigen die Nutzung der letzten Tage", async () => {
    const { app, usage } = setup();
    usage.record({ user: "anna", kind: "day", outcome: "claude", model: "claude-opus-5-5", inputTokens: 9_000, outputTokens: 2_000, latencyMs: 30_000 });
    usage.record({ user: "owner", kind: "macro", outcome: "failed", reason: "timeout", latencyMs: 180_000 });
    await usage.flush();

    const response = await request(app).get("/v1/admin/usage?days=2").set("Authorization", `Bearer ${TEST_TOKEN}`);

    expect(response.status).toBe(200);
    expect(response.body.today).toBe("2026-10-05");
    expect(response.body.days.map((day: { date: string }) => day.date)).toEqual(["2026-10-04", "2026-10-05"]);
    expect(response.body.days[1].outcomes).toEqual({ claude: 1, cache: 0, fallback: 0, failed: 1 });
    expect(response.body.days[1].users.anna.requests).toBe(1);
    expect(response.body.total.costUsd).toBeCloseTo(0.076);
  });

  it("pruefen den Zeitraum", async () => {
    const { app } = setup();
    for (const days of ["0", "91", "abc", "1.5"]) {
      const response = await request(app).get(`/v1/admin/usage?days=${days}`).set("Authorization", `Bearer ${TEST_TOKEN}`);
      expect(response.status).toBe(400);
    }
  });

  it("listen die Nutzer ohne Token", async () => {
    const { app, chefToken } = setup();

    const response = await request(app).get("/v1/admin/users").set("Authorization", `Bearer ${chefToken}`);

    expect(response.status).toBe(200);
    expect(response.body.users.map((user: { id: string }) => user.id)).toEqual(["owner", "anna", "chef"]);
    expect(response.body.users[1]).toEqual({ id: "anna", name: "Anna", admin: false, disabled: false, created_at: "2026-10-01T10:00:00.000Z" });
    expect(JSON.stringify(response.body)).not.toContain("token");
  });

  it("sind nur fuer Admins", async () => {
    const { app, annaToken } = setup();

    const usage = await request(app).get("/v1/admin/usage").set("Authorization", `Bearer ${annaToken}`);
    const users = await request(app).get("/v1/admin/users").set("Authorization", `Bearer ${annaToken}`);
    const anonymous = await request(app).get("/v1/admin/usage");

    expect(usage.status).toBe(403);
    expect(users.status).toBe(403);
    expect(anonymous.status).toBe(401);
  });
});
