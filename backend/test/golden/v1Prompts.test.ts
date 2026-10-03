import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { buildMacroUserMessage, MACRO_SYSTEM_PROMPT } from "../../src/plan/macroPrompt";
import { buildUserMessage, SYSTEM_PROMPT } from "../../src/plan/prompt";
import { SnapshotSchema } from "../../src/plan/snapshot";
import { buildWeekUserMessage, WEEK_SYSTEM_PROMPT } from "../../src/plan/weekPrompt";
import { macroContext } from "../plan/macroFixtures";
import { context } from "../plan/weekFixtures";

/**
 * Golden-Test des Triathlon-Umbaus: Ein v1-Snapshot (die App vor T2) ergibt Zeichen fuer Zeichen dieselben Prompts
 * wie vor Snapshot v2. `v1-prompts.json` wurde vor T2 mit `generate.ts` erzeugt; sie aendert sich nur mit einer
 * gewollten Prompt-Aenderung (dann neu erzeugen und im Commit begruenden).
 */
interface Golden {
  system: { day: string; week: string; macro: string };
  scenarios: Record<string, { day: string; day_with_wish: string; week: string; macro: string }>;
}

const golden: Golden = JSON.parse(readFileSync(path.join(__dirname, "v1-prompts.json"), "utf8"));
const scenarios = path.join(__dirname, "..", "..", "scenarios");
const v1Scenarios = readdirSync(scenarios)
  .filter((file) => file.endsWith(".json"))
  .filter((file) => JSON.parse(readFileSync(path.join(scenarios, file), "utf8")).schema_version === 1)
  .sort();

describe("v1-Snapshots ergeben dieselben Prompts wie vor v2", () => {
  it("deckt jedes v1-Szenario ab", () => {
    expect(Object.keys(golden.scenarios).sort()).toEqual(v1Scenarios);
  });

  it("System-Prompts unveraendert", () => {
    expect(SYSTEM_PROMPT).toBe(golden.system.day);
    expect(WEEK_SYSTEM_PROMPT).toBe(golden.system.week);
    expect(MACRO_SYSTEM_PROMPT).toBe(golden.system.macro);
  });

  it.each(v1Scenarios)("%s", (file) => {
    const snapshot = SnapshotSchema.parse(JSON.parse(readFileSync(path.join(scenarios, file), "utf8")));
    const expected = golden.scenarios[file];

    expect(buildUserMessage(snapshot, "2026-09-30")).toBe(expected.day);
    expect(buildUserMessage(snapshot, "2026-09-30", "mehr Technik", undefined, ["pull_buoy", "fins"])).toBe(expected.day_with_wish);
    expect(buildWeekUserMessage(snapshot, context())).toBe(expected.week);
    expect(buildMacroUserMessage(snapshot, macroContext())).toBe(expected.macro);
  });
});
