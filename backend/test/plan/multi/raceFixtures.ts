import { RacePlanRaw } from "../../../src/plan/multi/race";

/** Was Claude fuer eine Olympische Distanz liefert (Grundlage des Vertragsbeispiels und der Tests). */
export function olympicRaceRaw(): RacePlanRaw {
  return {
    overview: "Kontrolliert anschwimmen, auf dem Rad gleichmäßig unter der Schwelle fahren und beim Laufen ab Kilometer 5 zulegen. Ziel: etwa 2:55 h.",
    timeline: [
      { minutes_from_start: -180, title: "Frühstück", details: "Weißbrot mit Honig, eine Banane, ein Kaffee." },
      { minutes_from_start: -90, title: "Wechselzone einrichten", details: "Rad einhängen, Schuhe und Startnummer zurechtlegen." },
      { minutes_from_start: -20, title: "Einschwimmen", details: "Fünf Minuten locker, zwei kurze Steigerungen." },
      { minutes_from_start: 0, title: "Start", details: "Außen einordnen, die ersten 200 m ruhig." },
      { minutes_from_start: 200, title: "Nach dem Ziel", details: "Trinken, etwas essen, warm anziehen." }
    ],
    disciplines: [
      {
        sport: "swim",
        target_minutes: 30,
        pacing: [
          { segment: "Erste 200 m", target_type: "perceived_effort", target_value: 6, cue: "Ruhig starten", instructions: "Nicht mitreißen lassen, eigenen Rhythmus finden." },
          { segment: "Rest", target_type: "pace_per_100m", target_value: 118, cue: "Gleichmäßig", instructions: "Lange Züge, alle 6 Züge orientieren." }
        ],
        notes: "Im Gedränge Abstand halten."
      },
      {
        sport: "bike",
        target_minutes: 80,
        pacing: [{ segment: "Ganze Strecke", target_type: "heart_rate_zone", target_value: 3, cue: "Zone 3 halten", instructions: "Anstiege nicht überpacen." }],
        notes: "Jede 15 Minuten trinken."
      },
      {
        sport: "run",
        target_minutes: 58,
        pacing: [
          { segment: "Kilometer 1 bis 5", target_type: "pace_per_km", target_value: 345, cue: "Locker rein", instructions: "Die Beine vom Rad lösen lassen." },
          { segment: "Kilometer 6 bis 10", target_type: "pace_per_km", target_value: 335, cue: "Zulegen", instructions: "Wenn es gut geht, schneller werden." }
        ],
        notes: "An jeder Verpflegungsstelle einen Becher."
      }
    ],
    transitions: [
      { after_sport: "swim", checklist: ["Neo bis zur Hüfte öffnen", "Helm auf und zu", "Rad schieben bis zur Linie"] },
      { after_sport: "bike", checklist: ["Rad einhängen", "Helm ab", "Laufschuhe, Startnummer nach vorn"] }
    ],
    nutrition: {
      before: ["Am Vortag kohlenhydratreich essen", "Frühstück drei Stunden vor dem Start"],
      during: [
        { sport: "swim", carbs_g_per_hour: 0, fluid_ml_per_hour: 0, sodium_mg_per_hour: 0, notes: "Nichts." },
        { sport: "bike", carbs_g_per_hour: 60, fluid_ml_per_hour: 600, sodium_mg_per_hour: 500, notes: "Zwei Gels und eine Flasche Elektrolytgetränk." },
        { sport: "run", carbs_g_per_hour: 30, fluid_ml_per_hour: 400, sodium_mg_per_hour: 300, notes: "Ein Gel bei Kilometer 5, Wasser an den Stellen." }
      ],
      after: ["Innerhalb einer Stunde essen und trinken"]
    },
    checklist: ["Neoprenanzug", "Schwimmbrille (zwei)", "Helm", "Radschuhe", "Laufschuhe", "Startnummernband", "Gels", "Flaschen"]
  };
}
