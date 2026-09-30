import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";
import { z } from "zod";
import { TrainingPlanSchema, TrainingPlan } from "./plan";

export const StoredPlanSchema = z.object({
  /** Kalendertag (Zeitzone des Servers), fuer den der Plan erstellt wurde, YYYY-MM-DD. */
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  snapshotHash: z.string(),
  generatedAt: z.iso.datetime(),
  model: z.string(),
  plan: TrainingPlanSchema,
  adjustments: z.array(z.string())
});

export interface StoredPlan {
  date: string;
  snapshotHash: string;
  generatedAt: string;
  model: string;
  plan: TrainingPlan;
  adjustments: string[];
}

/** Haelt den letzten gueltigen Plan vor, als Antwort-Cache und als Fallback bei Claude-Ausfall. */
export interface PlanStore {
  latest(): Promise<StoredPlan | null>;
  save(plan: StoredPlan): Promise<void>;
}

const FILE_NAME = "latest-plan.json";

/** Speichert den Plan als eine JSON-Datei im Datenverzeichnis (im Container ein Docker-Volume). */
export class FilePlanStore implements PlanStore {
  private readonly file: string;

  constructor(private readonly dir: string) {
    this.file = path.join(dir, FILE_NAME);
  }

  async latest(): Promise<StoredPlan | null> {
    let content: string;
    try {
      content = await readFile(this.file, "utf8");
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") return null;
      throw error;
    }
    // Eine beschaedigte oder veraltete Datei zaehlt als "kein Plan", sie soll den Dienst nicht lahmlegen.
    try {
      const parsed = StoredPlanSchema.safeParse(JSON.parse(content));
      return parsed.success ? parsed.data : null;
    } catch {
      return null;
    }
  }

  async save(plan: StoredPlan): Promise<void> {
    await mkdir(this.dir, { recursive: true });
    // Erst in eine temporaere Datei schreiben und dann umbenennen: Ein Absturz mittendrin
    // hinterlaesst nie eine halb geschriebene Plan-Datei.
    const temporary = `${this.file}.${process.pid}.tmp`;
    await writeFile(temporary, JSON.stringify(plan, null, 2), "utf8");
    await rename(temporary, this.file);
  }
}

export class MemoryPlanStore implements PlanStore {
  constructor(private stored: StoredPlan | null = null) {}

  async latest(): Promise<StoredPlan | null> {
    return this.stored;
  }

  async save(plan: StoredPlan): Promise<void> {
    this.stored = plan;
  }
}
