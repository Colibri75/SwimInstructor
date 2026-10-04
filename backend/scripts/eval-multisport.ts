/**
 * Bewertung der Planung fuer mehrere Sportarten (Plan v2): schickt die Szenarien aus backend/scenarios/multisport/
 * durch den echten MultiPlanService, wie die App es tut (Gesamtplan, die naechsten sieben Tage mit der Vorgabe des
 * Gesamtplans, der Tag mit der Vorgabe der Woche, bei Feedback die Ueberarbeitung), und gibt Plaene, Korrekturen der
 * Sicherheitsschicht, automatische Pruefungen und Kosten als Markdown aus.
 *
 * Drei Arten:
 *   EVAL_REPLAY=1  spielt die Aufzeichnungen aus scenarios/multisport/recorded/ ab: ohne Netz, ohne Kosten.
 *                  Bis zum ersten echten Lauf sind sie synthetisch (von Hand gebaut, Modell "synthetisch").
 *   EVAL_RECORD=1  fragt Claude und schreibt jede Antwort als neue Aufzeichnung (Ordner: EVAL_RECORD_DIR).
 *   sonst          fragt Claude, ohne etwas zu schreiben.
 * Nur einige Szenarien: EVAL_ONLY=01,06 (Anfang des Dateinamens).
 *
 * Aufruf (mit Claude kostet es echtes Geld, 26 Anfragen fuer alle acht Szenarien):
 *   EVAL_REPLAY=1 npm run eval:multisport
 *   ANTHROPIC_API_KEY=sk-ant-... EVAL_RECORD=1 npm run eval:multisport > ../docs/eval-runs/multisport-$(date +%F).md
 * Auf dem Server ohne Node: scripts/eval-in-docker.sh multisport
 */
import Anthropic from "@anthropic-ai/sdk";
import { mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { planTimeouts } from "../src/config";
import { ClaudePlanGenerator, StructuredGenerator } from "../src/plan/generator";
import {
  formatScenarioReport,
  formatSummary,
  parseScenario,
  Recording,
  RecordingGenerator,
  ReplayGenerator,
  runScenario,
  ScenarioReport,
  stepSummary
} from "../src/plan/multi/scenarios";

const EFFORTS = ["low", "medium", "high", "xhigh", "max"] as const;
type Effort = (typeof EFFORTS)[number];

const SCENARIO_DIR = path.join(__dirname, "..", "scenarios", "multisport");
const RECORDED_DIR = path.join(SCENARIO_DIR, "recorded");

function fail(message: string): never {
  console.error(message);
  process.exit(1);
}

function claude(): { generator: StructuredGenerator; label: string } {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) fail("ANTHROPIC_API_KEY fehlt. Setze ihn in der Umgebung, er gehört nie ins Repo. Ohne Claude: EVAL_REPLAY=1.");
  const model = process.env.PLAN_MODEL ?? "claude-opus-5-5";
  const effort = (process.env.PLAN_EFFORT ?? "high") as Effort;
  if (!EFFORTS.includes(effort)) fail(`PLAN_EFFORT ungültig: ${effort} (erlaubt: ${EFFORTS.join(", ")})`);
  const timeouts = planTimeouts();
  const generator = new ClaudePlanGenerator(new Anthropic({ apiKey }), {
    model,
    effort,
    // Dieselben Zeitlimits wie der Server (gleiche Env-Datei): Was hier zu lange dauert, scheitert dort auch.
    timeoutMs: timeouts.claudeTimeoutMs,
    macroTimeoutMs: timeouts.claudeMacroTimeoutMs,
    serverFallback: process.env.PLAN_SERVER_FALLBACK !== "false"
  });
  return { generator, label: `Claude (${model}, Effort ${effort})` };
}

async function main(): Promise<void> {
  const replay = process.env.EVAL_REPLAY === "1";
  const record = process.env.EVAL_RECORD === "1";
  if (replay && record) fail("EVAL_REPLAY und EVAL_RECORD schließen sich aus.");
  const recordDir = process.env.EVAL_RECORD_DIR ?? RECORDED_DIR;
  const only = (process.env.EVAL_ONLY ?? "").split(",").map((entry) => entry.trim()).filter(Boolean);

  const files = readdirSync(SCENARIO_DIR)
    .filter((file) => file.endsWith(".json"))
    .filter((file) => only.length === 0 || only.some((prefix) => file.startsWith(prefix)))
    .sort();
  if (files.length === 0) fail(`Keine Szenarien${only.length > 0 ? ` für EVAL_ONLY=${only.join(",")}` : ""}.`);

  const live = replay ? undefined : claude();
  const mode = replay ? "Wiedergabe der Aufzeichnungen" : `${live!.label}${record ? ", mit Aufzeichnung" : ""}`;
  console.error(`${files.length} Szenarien, ${mode} ...`);

  const reports: ScenarioReport[] = [];
  const sources = new Set<string>();
  for (const file of files) {
    const name = file.replace(/\.json$/, "");
    const scenario = parseScenario(JSON.parse(readFileSync(path.join(SCENARIO_DIR, file), "utf8")));
    let generator: StructuredGenerator;
    let recorder: RecordingGenerator | undefined;
    if (replay) {
      const recording = JSON.parse(readFileSync(path.join(RECORDED_DIR, file), "utf8")) as Recording;
      for (const call of Object.values(recording)) if (call !== undefined) sources.add(call.source);
      generator = new ReplayGenerator(recording);
    } else {
      recorder = record ? new RecordingGenerator(live!.generator) : undefined;
      generator = recorder ?? live!.generator;
    }
    const started = Date.now();
    const report = await runScenario(name, scenario, generator);
    reports.push(report);
    console.error(`${name}: ${stepSummary(report)} (${((Date.now() - started) / 1000).toFixed(0)} s)`);
    if (recorder !== undefined) {
      // Nur vollstaendige Laeufe ersetzen die Aufzeichnung: Mit einer Luecke wuerde die Wiedergabe in der CI scheitern.
      const complete = [report.macro, report.week, report.day, report.revise].every((item) => item === undefined || item.error === undefined);
      if (complete) {
        mkdirSync(recordDir, { recursive: true });
        writeFileSync(path.join(recordDir, file), `${JSON.stringify(recorder.recording, null, 2)}\n`);
      } else {
        console.error(`${name}: nicht alle Stufen ok, die bisherige Aufzeichnung bleibt.`);
      }
    }
  }

  const out = [
    "# Bewertung der Planung für mehrere Sportarten (Plan v2)",
    "",
    `Quelle: ${mode}${sources.has("synthetic") ? " (synthetisch, von Hand gebaut: zeigt den Ablauf und die Sicherheitsschicht, nicht Claudes Qualität)" : ""}.`,
    "Die Prüfungen sind Heuristiken, die zeigen, wo man hinschauen sollte; die harten Grenzen setzt die Sicherheitsschicht.",
    "",
    "## Überblick",
    "",
    formatSummary(reports),
    "",
    ...reports.map((report) => formatScenarioReport(report))
  ];
  console.log(out.join("\n"));
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
