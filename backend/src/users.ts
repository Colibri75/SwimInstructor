import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import { mkdirSync, readFileSync, renameSync, statSync, writeFileSync } from "node:fs";
import path from "node:path";
import { z } from "zod";

/**
 * Nutzer des Servers: Jeder hat einen eigenen Token, eigene gespeicherte Daten und ein eigenes Aufrufbudget. Der Token
 * aus `API_TOKEN` ist der Besitzer (`owner`, Admin); weitere Nutzer stehen in `users.json` im Datenverzeichnis, nur mit
 * dem SHA-256 ihres Tokens. Verwaltet werden sie mit `node dist/cli/users.js` (siehe docs/backend-deploy.md).
 */
export interface AuthUser {
  id: string;
  name: string;
  admin: boolean;
}

export const OWNER_ID = "owner";
export const USERS_FILE = "users.json";
/** Kleinbuchstaben, Ziffern und Bindestrich: Die Kennung ist auch der Name des Datenordners. */
export const USER_ID_PATTERN = /^[a-z0-9][a-z0-9-]{0,31}$/;

const UserRecordSchema = z.object({
  id: z.string().regex(USER_ID_PATTERN),
  name: z.string().max(80),
  token_sha256: z.string().regex(/^[0-9a-f]{64}$/),
  created_at: z.string(),
  admin: z.boolean().optional(),
  disabled: z.boolean().optional()
});

const UsersFileSchema = z.object({ users: z.array(UserRecordSchema) });

export type UserRecord = z.infer<typeof UserRecordSchema>;

export function sha256Hex(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

/** Ein neuer Token: 32 zufaellige Bytes als Hex (64 Zeichen), wie `openssl rand -hex 32`. */
export function newToken(): string {
  return randomBytes(32).toString("hex");
}

export interface UserDirectory {
  authenticate(token: string): AuthUser | null;
}

/**
 * Liest `users.json` und liest sie neu, sobald sie sich aendert (hoechstens alle `recheckMs`), damit ein neuer Nutzer
 * ohne Neustart gilt. Eine kaputte Datei zaehlt als leer: Dann kommt nur noch der Besitzer herein.
 */
export class FileUserDirectory implements UserDirectory {
  private records: UserRecord[] = [];
  private loadedMtimeMs = -1;
  private checkedAt = -Infinity;
  private readonly ownerDigest: Buffer;
  private readonly file: string;

  constructor(
    ownerToken: string,
    dataDir: string,
    private readonly onProblem: (message: string) => void = () => {},
    private readonly recheckMs = 2_000,
    private readonly now: () => number = Date.now
  ) {
    this.ownerDigest = createHash("sha256").update(ownerToken).digest();
    this.file = path.join(dataDir, USERS_FILE);
  }

  authenticate(token: string): AuthUser | null {
    const digest = createHash("sha256").update(token).digest();
    // Beide Seiten gehasht: gleich lange Puffer fuer timingSafeEqual, die Laenge des Tokens verraet nichts.
    if (timingSafeEqual(digest, this.ownerDigest)) return { id: OWNER_ID, name: "Besitzer", admin: true };
    for (const record of this.current()) {
      if (record.disabled === true) continue;
      if (timingSafeEqual(digest, Buffer.from(record.token_sha256, "hex"))) {
        return { id: record.id, name: record.name, admin: record.admin === true };
      }
    }
    return null;
  }

  private current(): UserRecord[] {
    const now = this.now();
    if (now - this.checkedAt < this.recheckMs) return this.records;
    this.checkedAt = now;
    let mtimeMs: number;
    try {
      mtimeMs = statSync(this.file).mtimeMs;
    } catch {
      this.records = [];
      this.loadedMtimeMs = -1;
      return this.records;
    }
    if (mtimeMs === this.loadedMtimeMs) return this.records;
    this.loadedMtimeMs = mtimeMs;
    try {
      this.records = readUsers(this.file);
    } catch (error) {
      this.records = [];
      this.onProblem(`${USERS_FILE} nicht lesbar: ${(error as Error).message}`);
    }
    return this.records;
  }
}

/** Nur der Token aus der Konfiguration (Tests, Entwicklung). */
export class SingleUserDirectory implements UserDirectory {
  private readonly digest: Buffer;

  constructor(token: string) {
    this.digest = createHash("sha256").update(token).digest();
  }

  authenticate(token: string): AuthUser | null {
    const digest = createHash("sha256").update(token).digest();
    return timingSafeEqual(digest, this.digest) ? { id: OWNER_ID, name: "Besitzer", admin: true } : null;
  }
}

// MARK: - Datei lesen und schreiben (Verwaltung)

export function readUsers(file: string): UserRecord[] {
  let content: string;
  try {
    content = readFileSync(file, "utf8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return [];
    throw error;
  }
  const parsed = UsersFileSchema.parse(JSON.parse(content));
  const ids = new Set<string>();
  for (const user of parsed.users) {
    if (user.id === OWNER_ID || ids.has(user.id)) throw new Error(`Kennung doppelt oder reserviert: ${user.id}`);
    ids.add(user.id);
  }
  return parsed.users;
}

export function writeUsers(file: string, users: UserRecord[]): void {
  mkdirSync(path.dirname(file), { recursive: true });
  const temporary = `${file}.${process.pid}.tmp`;
  writeFileSync(temporary, `${JSON.stringify({ users }, null, 2)}\n`, { encoding: "utf8", mode: 0o600 });
  renameSync(temporary, file);
}

export class UserAdminError extends Error {}

/** Legt einen Nutzer an und liefert seinen Token (nur dieses eine Mal im Klartext). */
export function addUser(file: string, id: string, options: { name?: string; admin?: boolean; now?: Date } = {}): { user: UserRecord; token: string } {
  if (!USER_ID_PATTERN.test(id)) throw new UserAdminError("Kennung: Kleinbuchstaben, Ziffern und Bindestrich, höchstens 32 Zeichen");
  if (id === OWNER_ID) throw new UserAdminError(`"${OWNER_ID}" ist der Besitzer (Token aus API_TOKEN)`);
  const users = readUsers(file);
  if (users.some((user) => user.id === id)) throw new UserAdminError(`Nutzer "${id}" gibt es schon`);
  const token = newToken();
  const user: UserRecord = {
    id,
    name: (options.name ?? id).slice(0, 80),
    token_sha256: sha256Hex(token),
    created_at: (options.now ?? new Date()).toISOString(),
    ...(options.admin === true ? { admin: true } : {})
  };
  writeUsers(file, [...users, user]);
  return { user, token };
}

/** Neuer Token fuer einen Nutzer; der alte gilt sofort nicht mehr. */
export function rotateUser(file: string, id: string): string {
  const users = readUsers(file);
  const user = users.find((entry) => entry.id === id);
  if (user === undefined) throw new UserAdminError(`Nutzer "${id}" gibt es nicht`);
  const token = newToken();
  writeUsers(file, users.map((entry) => (entry.id === id ? { ...entry, token_sha256: sha256Hex(token) } : entry)));
  return token;
}

export function setUserDisabled(file: string, id: string, disabled: boolean): void {
  const users = readUsers(file);
  if (!users.some((entry) => entry.id === id)) throw new UserAdminError(`Nutzer "${id}" gibt es nicht`);
  writeUsers(
    file,
    users.map((entry) => {
      if (entry.id !== id) return entry;
      const { disabled: _old, ...rest } = entry;
      return disabled ? { ...rest, disabled: true } : rest;
    })
  );
}

export function removeUser(file: string, id: string): void {
  const users = readUsers(file);
  if (!users.some((entry) => entry.id === id)) throw new UserAdminError(`Nutzer "${id}" gibt es nicht`);
  writeUsers(file, users.filter((entry) => entry.id !== id));
}

/** Datenordner eines Nutzers: der Besitzer im Datenverzeichnis selbst (wie vor der Nutzertrennung), alle anderen darunter. */
export function userDataDir(dataDir: string, userId: string): string {
  return userId === OWNER_ID ? dataDir : path.join(dataDir, "users", userId);
}
