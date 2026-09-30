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
    const current = this.now();
    this.calls = this.calls.filter((time) => time > current - DAY_MS);
    const lastHour = this.calls.filter((time) => time > current - HOUR_MS).length;
    if (lastHour >= this.maxPerHour || this.calls.length >= this.maxPerDay) return false;
    this.calls.push(current);
    return true;
  }
}
