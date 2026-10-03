/**
 * Erzeugt `v1-prompts.json`: die Prompts, die das Backend vor Snapshot v2 fuer jedes v1-Szenario baute.
 * Nur einmal ausgefuehrt (vor T2) und eingecheckt; `v1Prompts.test.ts` prueft, dass v1-Snapshots heute
 * Zeichen fuer Zeichen dieselben Prompts ergeben. Neu erzeugen nur bei einer gewollten Prompt-Aenderung:
 *   npx tsx test/golden/generate.ts
 */
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { buildMacroUserMessage, MACRO_SYSTEM_PROMPT } from "../../src/plan/macroPrompt";
import { buildUserMessage, SYSTEM_PROMPT } from "../../src/plan/prompt";
import { SnapshotSchema } from "../../src/plan/snapshot";
import { buildWeekUserMessage, WEEK_SYSTEM_PROMPT } from "../../src/plan/weekPrompt";
import { macroContext } from "../plan/macroFixtures";
import { context } from "../plan/weekFixtures";

const scenarios = path.join(__dirname, "..", "..", "scenarios");
const result: Record<string, unknown> = {
  system: { day: SYSTEM_PROMPT, week: WEEK_SYSTEM_PROMPT, macro: MACRO_SYSTEM_PROMPT },
  scenarios: Object.fromEntries(
    readdirSync(scenarios)
      .filter((file) => file.endsWith(".json"))
      .sort()
      .map((file) => {
        const snapshot = SnapshotSchema.parse(JSON.parse(readFileSync(path.join(scenarios, file), "utf8")));
        return [
          file,
          {
            day: buildUserMessage(snapshot, "2026-09-30"),
            day_with_wish: buildUserMessage(snapshot, "2026-09-30", "mehr Technik", undefined, ["pull_buoy", "fins"]),
            week: buildWeekUserMessage(snapshot, context()),
            macro: buildMacroUserMessage(snapshot, macroContext())
          }
        ];
      })
  )
};
writeFileSync(path.join(__dirname, "v1-prompts.json"), `${JSON.stringify(result, null, 2)}\n`);
