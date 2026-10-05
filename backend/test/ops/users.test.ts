import { mkdtempSync, readFileSync, statSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import request from "supertest";
import { run } from "../../src/cli/users";
import { createApp } from "../../src/app";
import { createLogger } from "../../src/logger";
import {
  addUser,
  FileUserDirectory,
  OWNER_ID,
  readUsers,
  removeUser,
  rotateUser,
  setUserDisabled,
  sha256Hex,
  UserAdminError,
  userDataDir,
  USERS_FILE
} from "../../src/users";
import { TEST_TOKEN, testConfig } from "../helpers";

function tempDir(): string {
  return mkdtempSync(path.join(tmpdir(), "users-"));
}

describe("Nutzer: Verwaltung der Datei", () => {
  it("legt einen Nutzer mit gehashtem Token an und gibt den Token nur einmal heraus", () => {
    const file = path.join(tempDir(), USERS_FILE);

    const { user, token } = addUser(file, "anna", { name: "Anna", now: new Date("2026-10-05T10:00:00Z") });

    expect(token).toMatch(/^[0-9a-f]{64}$/);
    expect(user).toEqual({ id: "anna", name: "Anna", token_sha256: sha256Hex(token), created_at: "2026-10-05T10:00:00.000Z" });
    expect(readFileSync(file, "utf8")).not.toContain(token);
    expect(statSync(file).mode & 0o777).toBe(0o600);
    expect(readUsers(file)).toEqual([user]);
  });

  it("weist ungueltige, doppelte und reservierte Kennungen ab", () => {
    const file = path.join(tempDir(), USERS_FILE);
    addUser(file, "anna");

    expect(() => addUser(file, "anna")).toThrow(UserAdminError);
    expect(() => addUser(file, OWNER_ID)).toThrow(UserAdminError);
    expect(() => addUser(file, "Anna")).toThrow(UserAdminError);
    expect(() => addUser(file, "../etc")).toThrow(UserAdminError);
    expect(() => addUser(file, "a".repeat(33))).toThrow(UserAdminError);
  });

  it("dreht den Token, sperrt, entsperrt und loescht", () => {
    const file = path.join(tempDir(), USERS_FILE);
    const { token } = addUser(file, "anna");

    const rotated = rotateUser(file, "anna");
    expect(rotated).not.toBe(token);
    expect(readUsers(file)[0].token_sha256).toBe(sha256Hex(rotated));

    setUserDisabled(file, "anna", true);
    expect(readUsers(file)[0].disabled).toBe(true);
    setUserDisabled(file, "anna", false);
    expect(readUsers(file)[0].disabled).toBeUndefined();

    removeUser(file, "anna");
    expect(readUsers(file)).toEqual([]);
    expect(() => removeUser(file, "anna")).toThrow(UserAdminError);
  });

  it("legt die Daten des Besitzers wie bisher ins Datenverzeichnis, die anderen darunter", () => {
    expect(userDataDir("/data", OWNER_ID)).toBe("/data");
    expect(userDataDir("/data", "anna")).toBe(path.join("/data", "users", "anna"));
  });
});

describe("Nutzer: Anmeldung", () => {
  it("kennt den Besitzer aus API_TOKEN und die Nutzer aus der Datei", () => {
    const dir = tempDir();
    const { token } = addUser(path.join(dir, USERS_FILE), "anna", { name: "Anna" });
    const directory = new FileUserDirectory(TEST_TOKEN, dir, () => {}, 0);

    expect(directory.authenticate(TEST_TOKEN)).toEqual({ id: OWNER_ID, name: "Besitzer", admin: true });
    expect(directory.authenticate(token)).toEqual({ id: "anna", name: "Anna", admin: false });
    expect(directory.authenticate("falsch")).toBeNull();
  });

  it("liest die Datei neu, sobald sie sich aendert, und laesst gesperrte Nutzer nicht herein", () => {
    const dir = tempDir();
    const file = path.join(dir, USERS_FILE);
    const directory = new FileUserDirectory(TEST_TOKEN, dir, () => {}, 0);
    expect(directory.authenticate("x")).toBeNull();

    const { token } = addUser(file, "anna");
    expect(directory.authenticate(token)?.id).toBe("anna");

    setUserDisabled(file, "anna", true);
    // Gleiche Sekunde: die Aenderungszeit sicher verschieben, damit der Neuladetest nicht vom Dateisystem abhaengt.
    const later = new Date(Date.now() + 5_000);
    utimesSync(file, later, later);
    expect(directory.authenticate(token)).toBeNull();
  });

  it("laesst bei kaputter Datei nur den Besitzer herein und meldet das Problem", () => {
    const dir = tempDir();
    writeFileSync(path.join(dir, USERS_FILE), "{kaputt");
    const problems: string[] = [];
    const directory = new FileUserDirectory(TEST_TOKEN, dir, (message) => problems.push(message), 0);

    expect(directory.authenticate(TEST_TOKEN)?.id).toBe(OWNER_ID);
    expect(directory.authenticate("irgendwas")).toBeNull();
    expect(problems).toHaveLength(1);
  });

  it("legt den Nutzer fuer die Routen ab und meldet ihn in /v1/status", async () => {
    const dir = tempDir();
    const { token } = addUser(path.join(dir, USERS_FILE), "anna");
    const app = createApp(testConfig, createLogger(testConfig), { users: new FileUserDirectory(TEST_TOKEN, dir, () => {}, 0) });

    const anna = await request(app).get("/v1/status").set("Authorization", `Bearer ${token}`);
    const owner = await request(app).get("/v1/status").set("Authorization", `Bearer ${TEST_TOKEN}`);

    expect(anna.body).toEqual({ status: "authenticated", user: "anna" });
    expect(owner.body).toEqual({ status: "authenticated", user: OWNER_ID });
  });
});

describe("Nutzer: Kommandozeile", () => {
  it("legt an, listet und meldet Fehler mit Exitcode", () => {
    const dir = tempDir();
    const lines: string[] = [];
    const print = (line: string) => lines.push(line);

    expect(run(["add", "anna", "--name", "Anna Beispiel"], dir, print)).toBe(0);
    const token = lines[lines.length - 1];
    expect(token).toMatch(/^[0-9a-f]{64}$/);
    expect(readUsers(path.join(dir, USERS_FILE))[0].name).toBe("Anna Beispiel");

    lines.length = 0;
    expect(run(["list"], dir, print)).toBe(0);
    expect(lines.join("\n")).toContain("anna\tAnna Beispiel");
    expect(lines.join("\n")).not.toContain(token);

    lines.length = 0;
    expect(run(["add", "anna"], dir, print)).toBe(1);
    expect(lines[0]).toContain("gibt es schon");
    expect(run(["rotate"], dir, print)).toBe(1);
    expect(run(["unbekannt"], dir, print)).toBe(2);
    expect(run([], dir, print)).toBe(0);
  });
});
