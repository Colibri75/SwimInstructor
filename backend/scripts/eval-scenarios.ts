/**
 * Schickt die Szenarien aus backend/scenarios/ an die echte Claude-API, je Szenario einen Tagesplan, einen
 * Plan der naechsten sieben Tage und einen Gesamtplan bis zum Zieltag, und gibt Plaene, Korrekturen der
 * Sicherheitsschicht, automatische Zielpruefungen und Kosten als Markdown aus.
 *
 * Das ist die manuelle Pruefung fuer die Definition of Done von M5: Du bewertest jeden Plan von
 * Hand als sinnvoll oder nicht und haeltst das Ergebnis fest (docs/plan-eval.md, das gepflegte Dokument).
 * Die Zielpruefungen (src/plan/evaluation.ts) zeigen, wo man hinschauen sollte: Haelt der Plan das
 * Gesamtziel ein (Phase, Zielpace, ehrliche Aussage bei unrealistischem Ziel)?
 *
 * Aufruf (kostet echtes Geld, ca. drei Anfragen je Szenario):
 *   mkdir -p ../docs/eval-runs
 *   ANTHROPIC_API_KEY=sk-ant-... npm run eval:scenarios > ../docs/eval-runs/plan-eval-$(date +%F).md
 * Nur eine Art: EVAL_SCOPE=day, EVAL_SCOPE=week (die sieben Tage) oder EVAL_SCOPE=macro (Gesamtplan).
 */
import Anthropic from "@anthropic-ai/sdk";
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { checkDayPlanAgainstGoal, checkMacroPlanAgainstGoal, checkWeekPlanAgainstGoal, EvalCheck, formatChecks } from "../src/plan/evaluation";
import { ClaudePlanGenerator } from "../src/plan/generator";
import { assessGoal } from "../src/plan/goal";
import { macroWeekStarts, MacroPlanSchema } from "../src/plan/macro";
import { macroLimits, MacroContext, sanitizeMacro } from "../src/plan/macroSanity";
import { TrainingPlanSchema } from "../src/plan/plan";
import { estimateCostUsd, formatLimits, formatMacroLimits, formatMacroPlan, formatPlan, formatWeekLimits, formatWeekPlan } from "../src/plan/report";
import { dailyLimits, sanitizePlan } from "../src/plan/sanity";
import { SnapshotSchema } from "../src/plan/snapshot";
import { WeekPlanSchema } from "../src/plan/week";
import { sanitizeWeek, WeekContext, weekLimits } from "../src/plan/weekSanity";

const EFFORTS = ["low", "medium", "high", "xhigh", "max"] as const;
type Effort = (typeof EFFORTS)[number];

interface Row {
  scenario: string;
  kind: "Tag" | "7 Tage" | "Gesamt";
  status: string;
  corrections: number;
  checks: EvalCheck[];
}

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
  const scope = process.env.EVAL_SCOPE ?? "both";
  if (!["day", "week", "macro", "both"].includes(scope)) {
    console.error(`EVAL_SCOPE ungültig: ${scope} (erlaubt: day, week, macro, both)`);
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
  const calls = files.length * (scope === "both" ? 3 : 1);
  console.error(`Sende ${calls} Anfragen an ${model} (Effort ${effort}) ...`);

  const today = "2026-09-30";
  // Mittwoch 30.09.: die Woche ab heute, nichts geschwommen, jeder Tag frei.
  const weekContext: WeekContext = {
    today,
    dates: ["2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04"],
    unavailable: [],
    swumBefore: []
  };
  let totalCost = 0;
  const rows: Row[] = [];
  const body: string[] = [];

  for (const file of files) {
    const scenario = file.replace(/\.json$/, "");
    const snapshot = SnapshotSchema.parse(JSON.parse(readFileSync(path.join(dir, file), "utf8")));
    const goal = assessGoal(snapshot);
    body.push(`## ${scenario}`, "", "```json", JSON.stringify(snapshot, null, 2), "```", "");
    body.push(
      `**Gesamtziel:** ${snapshot.goal.distance_meters} m in ${Math.round(snapshot.goal.target_duration_seconds / 60)} min, noch ${snapshot.goal.days_until_goal} Tage, Phase \`${goal.phase}\`, ` +
        `Aufbau bis zur Zieldistanz ca. ${goal.weeksNeededForDistance} Wochen bei ${goal.weeksLeft} verbleibenden (${goal.distanceReachableSafely ? "erreichbar" : "nicht sicher erreichbar"}).`,
      ""
    );

    if (scope === "day" || scope === "both") {
      body.push("### Tagesplan", "", `**Grenzen für heute (gehen auch an Claude):** ${formatLimits(dailyLimits(snapshot))}`, "");
      const started = Date.now();
      try {
        const generated = await generator.generate({ snapshot, date: today });
        const seconds = ((Date.now() - started) / 1000).toFixed(1);
        const cost = estimateCostUsd(generated.model, generated.usage);
        totalCost += cost ?? 0;

        const parsed = TrainingPlanSchema.safeParse(generated.raw);
        if (!parsed.success) {
          body.push(`**Schema-Fehler:** ${JSON.stringify(parsed.error.issues.slice(0, 3))}`, "");
          rows.push({ scenario, kind: "Tag", status: "Schema-Fehler", corrections: 0, checks: [] });
        } else {
          const sanitized = sanitizePlan(parsed.data, snapshot);
          body.push("#### Claudes Plan (roh)", "", formatPlan(parsed.data), "");
          let finalPlan = parsed.data;
          if (sanitized.blocked !== null) {
            body.push(`**Von der Sicherheitsschicht GEBLOCKT:** ${sanitized.blocked}`, "");
          } else if (sanitized.adjustments.length > 0) {
            body.push("#### Korrekturen der Sicherheitsschicht", "", ...sanitized.adjustments.map((a) => `- ${a}`), "", "#### Plan nach Korrektur", "", formatPlan(sanitized.plan), "");
            finalPlan = sanitized.plan;
          } else {
            body.push("Die Sicherheitsschicht hat nichts geändert.", "");
          }
          const checks = checkDayPlanAgainstGoal(snapshot, finalPlan);
          body.push("#### Zielprüfung (automatisch)", "", formatChecks(checks), "");
          rows.push({ scenario, kind: "Tag", status: sanitized.blocked !== null ? "geblockt" : "ok", corrections: sanitized.adjustments.length, checks });
        }
        body.push(
          `Modell: \`${generated.model}\`, ${generated.usage.inputTokens} Token ein, ${generated.usage.outputTokens} Token aus, ${seconds} s, ca. ${cost === null ? "?" : "$" + cost.toFixed(3)}`,
          "",
          "**Bewertung Tagesplan (von Hand):** [ ] sinnvoll  [ ] nicht sinnvoll Begründung:",
          ""
        );
        console.error(`${scenario} (Tag): ok (${seconds} s)`);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        body.push(`**Fehler:** ${message}`, "");
        rows.push({ scenario, kind: "Tag", status: "Fehler", corrections: 0, checks: [] });
        console.error(`${scenario} (Tag): FEHLER ${message}`);
      }
    }

    if (scope === "week" || scope === "both") {
      body.push("### Die nächsten 7 Tage", "", `**Grenzen der 7 Tage (gehen auch an Claude):** ${formatWeekLimits(weekLimits(snapshot, weekContext))}`, "");
      const started = Date.now();
      try {
        const generated = await generator.generateWeek({ snapshot, context: weekContext });
        const seconds = ((Date.now() - started) / 1000).toFixed(1);
        const cost = estimateCostUsd(generated.model, generated.usage);
        totalCost += cost ?? 0;

        const parsed = WeekPlanSchema.safeParse(generated.raw);
        if (!parsed.success) {
          body.push(`**Schema-Fehler:** ${JSON.stringify(parsed.error.issues.slice(0, 3))}`, "");
          rows.push({ scenario, kind: "7 Tage", status: "Schema-Fehler", corrections: 0, checks: [] });
        } else {
          const sanitized = sanitizeWeek(parsed.data, snapshot, weekContext);
          body.push("#### Claudes Plan der 7 Tage (roh)", "", formatWeekPlan(parsed.data), "");
          let finalPlan = parsed.data;
          if (sanitized.blocked !== null) {
            body.push(`**Von der Sicherheitsschicht GEBLOCKT:** ${sanitized.blocked}`, "");
          } else if (sanitized.adjustments.length > 0) {
            body.push("#### Korrekturen der Sicherheitsschicht", "", ...sanitized.adjustments.map((a) => `- ${a}`), "", "#### Plan der 7 Tage nach Korrektur", "", formatWeekPlan(sanitized.plan), "");
            finalPlan = sanitized.plan;
          } else {
            body.push("Die Sicherheitsschicht hat nichts geändert.", "");
          }
          const checks = checkWeekPlanAgainstGoal(snapshot, finalPlan);
          body.push("#### Zielprüfung (automatisch)", "", formatChecks(checks), "");
          rows.push({ scenario, kind: "7 Tage", status: sanitized.blocked !== null ? "geblockt" : "ok", corrections: sanitized.adjustments.length, checks });
        }
        body.push(
          `Modell: \`${generated.model}\`, ${generated.usage.inputTokens} Token ein, ${generated.usage.outputTokens} Token aus, ${seconds} s, ca. ${cost === null ? "?" : "$" + cost.toFixed(3)}`,
          "",
          "**Bewertung 7 Tage (von Hand):** [ ] sinnvoll  [ ] nicht sinnvoll Begründung:",
          ""
        );
        console.error(`${scenario} (7 Tage): ok (${seconds} s)`);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        body.push(`**Fehler:** ${message}`, "");
        rows.push({ scenario, kind: "7 Tage", status: "Fehler", corrections: 0, checks: [] });
        console.error(`${scenario} (7 Tage): FEHLER ${message}`);
      }
    }

    if (scope === "macro" || scope === "both") {
      const goalDay = snapshot.goal.target_date.slice(0, 10);
      const macroContext: MacroContext = { today, goalDay, weeks: macroWeekStarts(today, goalDay) };
      body.push("### Gesamtplan bis zum Ziel", "", `**Wochen bis zum Zieltag ${goalDay}:** ${macroContext.weeks.length}. **Grenzen (gehen auch an Claude):** ${formatMacroLimits(macroLimits(snapshot, macroContext))}`, "");
      const started = Date.now();
      try {
        const generated = await generator.generateMacro({ snapshot, context: macroContext });
        const seconds = ((Date.now() - started) / 1000).toFixed(1);
        const cost = estimateCostUsd(generated.model, generated.usage);
        totalCost += cost ?? 0;

        const parsed = MacroPlanSchema.safeParse(generated.raw);
        if (!parsed.success) {
          body.push(`**Schema-Fehler:** ${JSON.stringify(parsed.error.issues.slice(0, 3))}`, "");
          rows.push({ scenario, kind: "Gesamt", status: "Schema-Fehler", corrections: 0, checks: [] });
        } else {
          const sanitized = sanitizeMacro(parsed.data, snapshot, macroContext);
          let finalPlan = sanitized.plan;
          if (sanitized.blocked !== null) {
            body.push(`**Von der Sicherheitsschicht GEBLOCKT:** ${sanitized.blocked}`, "");
          } else {
            body.push("#### Gesamtplan (nach der Sicherheitsschicht)", "", formatMacroPlan(sanitized.plan), "");
            if (sanitized.adjustments.length > 0) {
              body.push("#### Korrekturen der Sicherheitsschicht", "", ...sanitized.adjustments.map((a) => `- ${a}`), "");
            } else {
              body.push("Die Sicherheitsschicht hat nichts geändert.", "");
            }
          }
          const checks = checkMacroPlanAgainstGoal(snapshot, finalPlan);
          body.push("#### Zielprüfung (automatisch)", "", formatChecks(checks), "");
          rows.push({ scenario, kind: "Gesamt", status: sanitized.blocked !== null ? "geblockt" : "ok", corrections: sanitized.adjustments.length, checks });
        }
        body.push(
          `Modell: \`${generated.model}\`, ${generated.usage.inputTokens} Token ein, ${generated.usage.outputTokens} Token aus, ${seconds} s, ca. ${cost === null ? "?" : "$" + cost.toFixed(3)}`,
          "",
          "**Bewertung Gesamtplan (von Hand):** [ ] sinnvoll  [ ] nicht sinnvoll Begründung:",
          ""
        );
        console.error(`${scenario} (Gesamt): ok (${seconds} s)`);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        body.push(`**Fehler:** ${message}`, "");
        rows.push({ scenario, kind: "Gesamt", status: "Fehler", corrections: 0, checks: [] });
        console.error(`${scenario} (Gesamt): FEHLER ${message}`);
      }
    }
  }

  const out: string[] = [
    "# Plan-Bewertung der Szenarien (Tag, 7 Tage und Gesamtplan, mit Zielprüfung)",
    "",
    `Modell: \`${model}\`, Effort: \`${effort}\`, Stichtag: ${today}, Umfang: ${scope}`,
    "",
    "## Überblick",
    "",
    "| Szenario | Plan | Status | Korrekturen | Zielprüfung |",
    "|---|---|---|---|---|",
    ...rows.map((row) => {
      const failed = row.checks.filter((c) => !c.ok);
      const verdict = row.checks.length === 0 ? "–" : failed.length === 0 ? `alle ${row.checks.length} bestanden` : `${failed.length} von ${row.checks.length} offen: ${failed.map((c) => c.name).join("; ")}`;
      return `| ${row.scenario} | ${row.kind} | ${row.status} | ${row.corrections} | ${verdict} |`;
    }),
    "",
    ...body,
    "---",
    "",
    `Geschätzte Gesamtkosten dieses Laufs: ca. $${totalCost.toFixed(3)}`
  ];
  console.log(out.join("\n"));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
