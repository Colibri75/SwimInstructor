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

const Sha256Schema = z.string().regex(/^[0-9a-f]{64}$/);

const UserRecordSchema = z.object({
  id: z.string().regex(USER_ID_PATTERN),
  name: z.string().max(80),
  /** Token von Hand (CLI: `add`, `rotate`). Fehlt bei Nutzern, die sich nur mit Apple anmelden. */
  token_sha256: Sha256Schema.optional(),
  /** Sitzungen aus "Mit Apple anmelden", eine je Gerät (die neueste zuletzt, höchstens `MAX_SESSIONS`). */
  token_sha256s: z.array(Sha256Schema).optional(),
  /** Stabile Kennung der Apple-ID (`sub` im Identitaetstoken), nur bei Apple-Nutzern. */
  apple_sub: z.string().min(1).max(255).optional(),
  email: z.string().max(320).optional(),
  created_at: z.string(),
  admin: z.boolean().optional(),
  disabled: z.boolean().optional()
});

const UsersFileSchema = z.object({ users: z.array(UserRecordSchema) });

export type UserRecord = z.infer<typeof UserRecordSchema>;

/** Hoechstens so viele Apple-Sitzungen je Nutzer; eine weitere verdraengt die aelteste. */
export const MAX_SESSIONS = 10;

export function sha256Hex(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

/** Ein neuer Token: 32 zufaellige Bytes als Hex (64 Zeichen), wie `openssl rand -hex 32`. */
export function newToken(): string {
  return randomBytes(32).toString("hex");
}

export interface UserDirectory {
  authenticate(token: string): AuthUser | null;
  /** Nach einer Aenderung von `users.json` durch den Server selbst: sofort neu lesen statt erst nach `recheckMs`. */
  invalidate?(): void;
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
      if (recordDigests(record).some((hex) => timingSafeEqual(digest, Buffer.from(hex, "hex")))) {
        return { id: record.id, name: record.name, admin: record.admin === true };
      }
    }
    return null;
  }

  invalidate(): void {
    this.checkedAt = -Infinity;
    this.loadedMtimeMs = -1;
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

/** Alle gueltigen Token-Hashes eines Nutzers: der von Hand und die Apple-Sitzungen. */
function recordDigests(record: UserRecord): string[] {
  return [...(record.token_sha256 === undefined ? [] : [record.token_sha256]), ...(record.token_sha256s ?? [])];
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
  const subs = new Set<string>();
  for (const user of parsed.users) {
    if (user.id === OWNER_ID || ids.has(user.id)) throw new Error(`Kennung doppelt oder reserviert: ${user.id}`);
    ids.add(user.id);
    if (user.apple_sub !== undefined) {
      if (subs.has(user.apple_sub)) throw new Error(`Apple-ID doppelt: ${user.id}`);
      subs.add(user.apple_sub);
    }
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

/** Neuer Token fuer einen Nutzer; der alte und alle Apple-Sitzungen gelten sofort nicht mehr. */
export function rotateUser(file: string, id: string): string {
  const users = readUsers(file);
  const user = users.find((entry) => entry.id === id);
  if (user === undefined) throw new UserAdminError(`Nutzer "${id}" gibt es nicht`);
  const token = newToken();
  writeUsers(
    file,
    users.map((entry) => {
      if (entry.id !== id) return entry;
      const { token_sha256s: _sessions, ...rest } = entry;
      return { ...rest, token_sha256: sha256Hex(token) };
    })
  );
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

// MARK: - Mit Apple anmelden

export interface AppleIdentity {
  sub: string;
  email?: string;
}

export type AppleSignInResult =
  | { status: "ok"; token: string; user: UserRecord; created: boolean }
  /** Gesperrt: neu angelegt bei `APPLE_SIGNUP=closed` oder vom Besitzer gesperrt. Kein Token. */
  | { status: "disabled"; user: UserRecord; created: boolean };

/**
 * Kennung eines Apple-Nutzers: "a-" und ein Stueck des SHA-256 der Apple-Kennung (passt zu `USER_ID_PATTERN`, verraet
 * nichts ueber die Apple-ID). Ist sie schon vergeben, wird das Stueck laenger.
 */
export function appleUserId(sub: string, taken: (id: string) => boolean): string {
  const digest = sha256Hex(`apple:${sub}`);
  for (const length of [12, 16, 20, 24, 30]) {
    const id = `a-${digest.slice(0, length)}`;
    if (!taken(id)) return id;
  }
  throw new UserAdminError("Keine freie Kennung fuer diese Apple-ID");
}

/**
 * Findet den Nutzer zur Apple-ID oder legt ihn an und gibt ihm eine neue Sitzung (nur ihr SHA-256 wird gespeichert).
 * Bei `signupOpen = false` entsteht ein neuer Nutzer gesperrt; der Besitzer gibt ihn mit `enable` frei.
 */
export function signInWithApple(
  file: string,
  identity: AppleIdentity,
  options: { name?: string; signupOpen: boolean; now?: Date }
): AppleSignInResult {
  const users = readUsers(file);
  const name = options.name?.trim().slice(0, 80) || undefined;
  let user = users.find((entry) => entry.apple_sub === identity.sub);
  const created = user === undefined;
  if (user === undefined) {
    const ids = new Set(users.map((entry) => entry.id));
    user = {
      id: appleUserId(identity.sub, (id) => id === OWNER_ID || ids.has(id)),
      name: name ?? "Apple-ID",
      apple_sub: identity.sub,
      ...(identity.email === undefined ? {} : { email: identity.email.slice(0, 320) }),
      created_at: (options.now ?? new Date()).toISOString(),
      ...(options.signupOpen ? {} : { disabled: true })
    };
  } else {
    // Den Namen gibt Apple nur bei der ersten Anmeldung heraus: ein spaeter mitgeschickter ersetzt den alten.
    user = {
      ...user,
      ...(name === undefined ? {} : { name }),
      ...(identity.email === undefined ? {} : { email: identity.email.slice(0, 320) })
    };
  }

  let token: string | undefined;
  if (user.disabled !== true) {
    token = newToken();
    user = { ...user, token_sha256s: [...(user.token_sha256s ?? []), sha256Hex(token)].slice(-MAX_SESSIONS) };
  }
  const saved = user;
  writeUsers(file, created ? [...users, saved] : users.map((entry) => (entry.id === saved.id ? saved : entry)));
  return token === undefined ? { status: "disabled", user: saved, created } : { status: "ok", token, user: saved, created };
}

/** Datenordner eines Nutzers: der Besitzer im Datenverzeichnis selbst (wie vor der Nutzertrennung), alle anderen darunter. */
export function userDataDir(dataDir: string, userId: string): string {
  return userId === OWNER_ID ? dataDir : path.join(dataDir, "users", userId);
}
