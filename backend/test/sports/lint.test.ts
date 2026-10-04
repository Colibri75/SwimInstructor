import { readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { SPORTS } from "../../src/sports/registry";

/**
 * Sorgt dafuer, dass ausserhalb von src/sports/ niemand nach einer bestimmten Sportart verzweigt. Sonst waere
 * eine neue Sportart wieder eine Aenderung quer durch den Code statt einer neuen Definition. Gegenstueck in
 * Swift: SportLintTests. Geprueft werden die Kennungen aller angemeldeten Sportarten.
 */
const SRC = path.join(__dirname, "../../src");
const ALLOWED = path.join(SRC, "sports") + path.sep;
const FORBIDDEN = new RegExp(`["'\`](${SPORTS.ids.join("|")})["'\`]`);

function sourceFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const full = path.join(dir, name);
    if (statSync(full).isDirectory()) return sourceFiles(full);
    return full.endsWith(".ts") ? [full] : [];
  });
}

describe("Sportart-Logik nur in src/sports/", () => {
  it("findet keine Sport-Kennung ausserhalb der Module", () => {
    const files = sourceFiles(SRC).filter((file) => !file.startsWith(ALLOWED));
    expect(files.length).toBeGreaterThan(20);

    const violations = files.flatMap((file) =>
      readFileSync(file, "utf8")
        .split("\n")
        .map((line, index) => ({ line, index }))
        .filter(({ line }) => FORBIDDEN.test(line))
        .map(({ line, index }) => `${path.relative(SRC, file)}:${index + 1}: ${line.trim()}`)
    );
    expect(violations).toEqual([]);
  });

  it("erkennt, was es erkennen soll", () => {
    expect(FORBIDDEN.test(`if (sport === "run") {`)).toBe(true);
    expect(FORBIDDEN.test(`case 'bike':`)).toBe(true);
    expect(FORBIDDEN.test(`const label = "running";`)).toBe(false);
    expect(FORBIDDEN.test(`// swim im Kommentar`)).toBe(false);
  });
});
