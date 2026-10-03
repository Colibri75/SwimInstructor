import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import { z } from "zod";
import { INTENSITIES, SESSION_TYPES } from "../plan";
import { DayPlanV2 } from "./daySanity";
import { MultiDayPlanRaw, StepSchema } from "./schemas";

/**
 * Der letzte gueltige Tagesplan v2, als Antwort-Cache und als Fallback bei Claude-Ausfall. Eigene Datei neben dem
 * Plan v1 (latest-plan.json): Alte und neue App koennen am selben Tag beide planen, ohne sich den Plan zu ueberschreiben.
 */
const StoredSessionSchema = z.object({
  sport: z.string(),
  session_type: z.enum(SESSION_TYPES),
  intensity: z.enum(INTENSITIES),
  focus: z.string(),
  test: z.object({ id: z.string(), display_name: z.string(), maximal_effort: z.boolean(), produces: z.array(z.string()) }).nullable(),
  amount: z.number(),
  unit: z.enum(["meters", "minutes"]),
  distance_meters: z.number(),
  duration_minutes: z.number(),
  steps: z.array(StepSchema)
});

export const StoredDayV2Schema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  hash: z.string(),
  generatedAt: z.iso.datetime(),
  model: z.string(),
  plan: z.object({ rationale: z.string(), sessions: z.array(StoredSessionSchema), coach_notes: z.array(z.string()) }),
  adjustments: z.array(z.string())
});

export interface StoredDayV2 {
  date: string;
  hash: string;
  generatedAt: string;
  model: string;
  plan: DayPlanV2;
  adjustments: string[];
}

export interface DayPlanStoreV2 {
  latest(): Promise<StoredDayV2 | null>;
  save(plan: StoredDayV2): Promise<void>;
}

/** Ein gespeicherter Plan in der Form, die Claude liefert, damit er noch einmal durch die Sicherheitsschicht kann. */
export function asRawDayPlan(plan: DayPlanV2): MultiDayPlanRaw {
  return {
    rationale: plan.rationale,
    coach_notes: plan.coach_notes,
    sessions: plan.sessions.map((session) => ({
      sport: session.sport,
      session_type: session.session_type,
      intensity: session.intensity,
      focus: session.focus,
      test_id: session.test?.id ?? null,
      steps: session.steps.map((step) => ({ ...step, equipment: [...step.equipment] }))
    }))
  };
}

export const DAY_PLAN_V2_FILE = "latest-plan-v2.json";

export class FileDayPlanStoreV2 implements DayPlanStoreV2 {
  private readonly file: string;

  constructor(private readonly dir: string) {
    this.file = path.join(dir, DAY_PLAN_V2_FILE);
  }

  async latest(): Promise<StoredDayV2 | null> {
    let content: string;
    try {
      content = await readFile(this.file, "utf8");
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") return null;
      throw error;
    }
    // Eine beschaedigte oder veraltete Datei zaehlt als "kein Plan".
    try {
      const parsed = StoredDayV2Schema.safeParse(JSON.parse(content));
      return parsed.success ? (parsed.data as StoredDayV2) : null;
    } catch {
      return null;
    }
  }

  async save(plan: StoredDayV2): Promise<void> {
    await mkdir(this.dir, { recursive: true });
    const temporary = `${this.file}.${process.pid}.tmp`;
    await writeFile(temporary, JSON.stringify(plan, null, 2), "utf8");
    await rename(temporary, this.file);
  }
}

export class MemoryDayPlanStoreV2 implements DayPlanStoreV2 {
  constructor(private stored: StoredDayV2 | null = null) {}

  async latest(): Promise<StoredDayV2 | null> {
    return this.stored;
  }

  async save(plan: StoredDayV2): Promise<void> {
    this.stored = plan;
  }
}
