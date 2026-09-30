/**
 * Schickt die fuenf Szenarien aus backend/scenarios/ an die echte Claude-API und gibt je Szenario
 * den Plan, die Korrekturen der Sicherheitsschicht und die Kosten als Markdown aus.
 *
 * Das ist die manuelle Pruefung fuer die Definition of Done von M5: Du bewertest jeden Plan von
 * Hand als sinnvoll oder nicht und haeltst das Ergebnis fest (docs/plan-eval.md, das gepflegte Dokument).
 *
 * Aufruf (kostet echtes Geld, ca. fuenf Anfragen):
 *   mkdir -p ../docs/eval-runs
 *   ANTHROPIC_API_KEY=sk-ant-... npm run eval:scenarios > ../docs/eval-runs/plan-eval-$(date +%F).md
 */
import Anthropic from "@anthropic-ai/sdk";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { ClaudePlanGenerator } from "../src/plan/generator";
import { TrainingPlanSchema } from "../src/plan/plan";
import { estimateCostUsd, formatLimits, formatPlan } from "../src/plan/report";
import { dailyLimits, sanitizePlan } from "../src/plan/sanity";
import { SnapshotSchema } from "../src/plan/snapshot";

const EFFORTS = ["low", "medium", "high", "xhigh", "max"] as const;
type Effort = (typeof EFFORTS)[number];

async function main(): Promise<void> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    console.error("ANTHROPIC_API_KEY fehlt. Setze ihn in der Umgebung, er gehört nie ins Repo.");
    process.exit(1);
  }
  const model = process.env.PLAN_MODEL ?? "claude-opus-5-5";
  const effort = (process.env.PLAN_EFFORT ?? "medium") as Effort;
  if (!EFFORTS.includes(effort)) {
    console.error(`PLAN_EFFORT ungültig: ${effort} (erlaubt: ${EFFORTS.join(", ")})`);
    process.exit(1);
  }

  const generator = new ClaudePlanGenerator(new Anthropic({ apiKey }), {
    model,
    effort,
    timeoutMs: 85_000,
    serverFallback: process.env.PLAN_SERVER_FALLBACK !== "false"
  });

  const dir = path.join(__dirname, "..", "scenarios");
  const files = readdirSync(dir).filter((file) => file.endsWith(".json")).sort();
  console.error(`Sende ${files.length} Anfragen an ${model} (Effort ${effort}) ...`);

  const today = "2026-09-30";
  let totalCost = 0;
  const out: string[] = [`# Plan-Bewertung der fünf Szenarien`, "", `Modell: \`${model}\`, Effort: \`${effort}\`, Stichtag: ${today}`, ""];

  for (const file of files) {
    const snapshot = SnapshotSchema.parse(JSON.parse(readFileSync(path.join(dir, file), "utf8")));
    out.push(`## ${file.replace(/\.json$/, "")}`, "", "```json", JSON.stringify(snapshot, null, 2), "```", "");
    out.push(`**Grenzen für heute (gehen auch an Claude):** ${formatLimits(dailyLimits(snapshot))}`, "");

    const started = Date.now();
    try {
      const generated = await generator.generate({ snapshot, date: today });
      const seconds = ((Date.now() - started) / 1000).toFixed(1);
      const cost = estimateCostUsd(generated.model, generated.usage);
      totalCost += cost ?? 0;

      const parsed = TrainingPlanSchema.safeParse(generated.raw);
      if (!parsed.success) {
        out.push(`**Schema-Fehler:** ${JSON.stringify(parsed.error.issues.slice(0, 3))}`, "");
        continue;
      }
      const sanitized = sanitizePlan(parsed.data, snapshot);

      out.push("### Claudes Plan (roh)", "", formatPlan(parsed.data), "");
      if (sanitized.blocked !== null) {
        out.push(`**Von der Sicherheitsschicht GEBLOCKT:** ${sanitized.blocked}`, "");
      } else if (sanitized.adjustments.length > 0) {
        out.push("### Korrekturen der Sicherheitsschicht", "", ...sanitized.adjustments.map((a) => `- ${a}`), "", "### Plan nach Korrektur", "", formatPlan(sanitized.plan), "");
      } else {
        out.push("Die Sicherheitsschicht hat nichts geändert.", "");
      }
      out.push(
        `Modell: \`${generated.model}\`, ${generated.usage.inputTokens} Token ein, ${generated.usage.outputTokens} Token aus, ${seconds} s, ca. ${cost === null ? "?" : "$" + cost.toFixed(3)}`,
        "",
        "**Bewertung (von Hand):** [ ] sinnvoll  [ ] nicht sinnvoll Begründung:",
        ""
      );
      console.error(`${file}: ok (${seconds} s)`);
    } catch (error) {
      out.push(`**Fehler:** ${error instanceof Error ? error.message : String(error)}`, "");
      console.error(`${file}: FEHLER ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  out.push(`---`, "", `Geschätzte Gesamtkosten dieses Laufs: ca. $${totalCost.toFixed(3)}`);
  console.log(out.join("\n"));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
