import { GenerationBudget } from "../../src/plan/budget";

describe("GenerationBudget", () => {
  const HOUR = 60 * 60 * 1000;

  it("erlaubt Aufrufe bis zum Stundenlimit und sperrt danach", () => {
    let now = 0;
    const budget = new GenerationBudget(3, 100, () => now);

    expect([budget.tryConsume(), budget.tryConsume(), budget.tryConsume()]).toEqual([true, true, true]);
    expect(budget.tryConsume()).toBe(false);
  });

  it("gibt nach einer Stunde wieder Aufrufe frei (Gleitfenster)", () => {
    let now = 0;
    const budget = new GenerationBudget(2, 100, () => now);
    budget.tryConsume();
    budget.tryConsume();
    expect(budget.tryConsume()).toBe(false);

    now = HOUR + 1;

    expect(budget.tryConsume()).toBe(true);
  });

  it("begrenzt zusaetzlich pro Tag, auch wenn das Stundenlimit nie erreicht wird", () => {
    let now = 0;
    const budget = new GenerationBudget(2, 3, () => now);
    const results: boolean[] = [];
    for (let hour = 0; hour < 5; hour++) {
      now = hour * 2 * HOUR; // nie mehr als ein Aufruf pro Stunde
      results.push(budget.tryConsume());
    }

    expect(results).toEqual([true, true, true, false, false]);
  });

  it("gibt nach 24 Stunden das Tageslimit wieder frei", () => {
    let now = 0;
    const budget = new GenerationBudget(10, 1, () => now);
    budget.tryConsume();
    expect(budget.tryConsume()).toBe(false);

    now = 24 * HOUR + 1;

    expect(budget.tryConsume()).toBe(true);
  });

  it("verbraucht bei einer Ablehnung kein Budget", () => {
    let now = 0;
    const budget = new GenerationBudget(1, 100, () => now);
    budget.tryConsume();
    budget.tryConsume(); // abgelehnt

    now = HOUR + 1;

    expect(budget.tryConsume()).toBe(true);
    expect(budget.tryConsume()).toBe(false);
  });
});
