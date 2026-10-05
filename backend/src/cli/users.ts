import path from "node:path";
import { addUser, OWNER_ID, readUsers, removeUser, rotateUser, setUserDisabled, UserAdminError, USERS_FILE } from "../users";

/**
 * Verwaltet die Nutzer des Servers (Datei `users.json` im Datenverzeichnis). Auf dem Server im Container:
 *
 *   docker exec swiminstructor-backend node dist/cli/users.js add anna --name "Anna"
 *   docker exec swiminstructor-backend node dist/cli/users.js list
 *
 * Der Token erscheint nur beim Anlegen und bei `rotate`; gespeichert wird nur sein SHA-256. Der Server liest die Datei
 * bei Aenderungen selbst neu, ein Neustart ist nicht noetig.
 */
const USAGE = `Nutzer verwalten:
  add <kennung> [--name "Name"] [--admin]   neuen Nutzer anlegen, gibt den Token aus
  list                                      alle Nutzer
  rotate <kennung>                          neuer Token, der alte gilt sofort nicht mehr
  disable <kennung> | enable <kennung>      sperren oder entsperren
  remove <kennung>                          Nutzer löschen (seine gespeicherten Pläne bleiben im Ordner users/<kennung>)`;

export function run(args: string[], dataDir: string, print: (line: string) => void): number {
  const file = path.join(dataDir, USERS_FILE);
  const [command, id, ...rest] = args;
  try {
    switch (command) {
      case "add": {
        requireId(id);
        const nameIndex = rest.indexOf("--name");
        const name = nameIndex >= 0 ? rest[nameIndex + 1] : undefined;
        const { user, token } = addUser(file, id, { name, admin: rest.includes("--admin") });
        print(`Nutzer "${user.id}" (${user.name}) angelegt${user.admin ? " als Admin" : ""}.`);
        print(`Token (nur jetzt sichtbar, in der App unter Einstellungen > Server eintragen):`);
        print(token);
        return 0;
      }
      case "list": {
        print(`${OWNER_ID}\tBesitzer\tAdmin\t(Token aus API_TOKEN)`);
        for (const user of readUsers(file)) {
          print([user.id, user.name, user.admin ? "Admin" : "", user.disabled ? "gesperrt" : "aktiv", user.created_at].join("\t"));
        }
        return 0;
      }
      case "rotate": {
        requireId(id);
        const token = rotateUser(file, id);
        print(`Neuer Token für "${id}" (nur jetzt sichtbar):`);
        print(token);
        return 0;
      }
      case "disable":
      case "enable":
        requireId(id);
        setUserDisabled(file, id, command === "disable");
        print(`Nutzer "${id}" ${command === "disable" ? "gesperrt" : "entsperrt"}.`);
        return 0;
      case "remove":
        requireId(id);
        removeUser(file, id);
        print(`Nutzer "${id}" gelöscht.`);
        return 0;
      default:
        print(USAGE);
        return command === undefined || command === "help" ? 0 : 2;
    }
  } catch (error) {
    if (error instanceof UserAdminError) {
      print(`Fehler: ${error.message}`);
      return 1;
    }
    throw error;
  }
}

function requireId(id: string | undefined): asserts id is string {
  if (id === undefined || id === "") throw new UserAdminError("Kennung fehlt");
}

if (require.main === module) {
  process.exitCode = run(process.argv.slice(2), process.env.DATA_DIR?.trim() || "./data", (line) => console.log(line));
}
