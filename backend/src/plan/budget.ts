const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;

/**
 * Begrenzt, wie oft der Server Claude aufruft (Gleitfenster pro Stunde und pro Tag). Ein
 * durchgesickerter Token soll nicht unbegrenzt Kosten erzeugen. Ist das Budget erschoepft, liefert der
 * Service den letzten gueltigen Plan statt eines neuen. Der Zaehler liegt im Speicher und beginnt
 * nach einem Neustart von vorn, das reicht als Kostenbremse.
 */
export class GenerationBudget {
  private calls: number[] = [];

  constructor(
    private readonly maxPerHour: number,
    private readonly maxPerDay: number,
    private readonly now: () => number = Date.now
  ) {}

  /** Verbraucht einen Aufruf, wenn das Budget reicht, und meldet, ob er erlaubt ist. */
  tryConsume(): boolean {
    if (!this.available()) return false;
    this.consume();
    return true;
  }

  /** Ob noch ein Aufruf frei ist, ohne ihn zu verbrauchen. */
  available(): boolean {
    const current = this.now();
    this.calls = this.calls.filter((time) => time > current - DAY_MS);
    const lastHour = this.calls.filter((time) => time > current - HOUR_MS).length;
    return lastHour < this.maxPerHour && this.calls.length < this.maxPerDay;
  }

  consume(): void {
    this.calls.push(this.now());
  }

  /** Verbraucht in allen Budgets einen Aufruf, aber nur, wenn alle noch einen frei haben. */
  static tryConsumeAll(budgets: readonly GenerationBudget[]): boolean {
    if (!budgets.every((budget) => budget.available())) return false;
    for (const budget of budgets) budget.consume();
    return true;
  }
}

/** Ein Budget je Nutzer, mit denselben Grenzen, angelegt beim ersten Aufruf. */
export class UserBudgets {
  private readonly budgets = new Map<string, GenerationBudget>();

  constructor(
    private readonly maxPerHour: number,
    private readonly maxPerDay: number,
    private readonly now: () => number = Date.now
  ) {}

  for(user: string): GenerationBudget {
    let budget = this.budgets.get(user);
    if (budget === undefined) {
      budget = new GenerationBudget(this.maxPerHour, this.maxPerDay, this.now);
      this.budgets.set(user, budget);
    }
    return budget;
  }
}
