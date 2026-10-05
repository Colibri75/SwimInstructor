import { GeoLocation } from "./multi/schemas";

/**
 * Wettervorhersage fuer die Planung: je Tag Temperatur, Niederschlag, Wind und Wettercode (WMO). Quelle ist Open-Meteo
 * (frei, ohne Schluessel). Die App schickt nur einen gerundeten Ort (etwa 10 km genau); ohne Ort oder bei einem Fehler
 * plant der Server ohne Wetter.
 */
export interface DayWeather {
  date: string;
  temp_max_c: number;
  temp_min_c: number;
  precipitation_mm: number;
  /** Hoechste Regenwahrscheinlichkeit des Tages in Prozent. */
  precipitation_probability: number;
  wind_max_kmh: number;
  /** WMO-Wettercode (0 klar, 61 Regen, 95 Gewitter, ...). */
  weather_code: number;
}

export interface WeatherProvider {
  /** Vorhersage fuer die Tage `dates` (soweit vorhanden); wirft bei Netz- oder Formatfehlern. */
  forecast(location: GeoLocation, dates: readonly string[]): Promise<DayWeather[]>;
}

/** Auf eine Nachkommastelle gerundet: Der Server kennt den Ort nie genauer als die App ihn schickt. */
export function roundLocation(location: GeoLocation): GeoLocation {
  return { latitude: Math.round(location.latitude * 10) / 10, longitude: Math.round(location.longitude * 10) / 10 };
}

const DAILY = ["weather_code", "temperature_2m_max", "temperature_2m_min", "precipitation_sum", "precipitation_probability_max", "wind_speed_10m_max"] as const;

interface OpenMeteoDaily {
  time: string[];
  weather_code: Array<number | null>;
  temperature_2m_max: Array<number | null>;
  temperature_2m_min: Array<number | null>;
  precipitation_sum: Array<number | null>;
  precipitation_probability_max: Array<number | null>;
  wind_speed_10m_max: Array<number | null>;
}

/** Open-Meteo mit kleinem Cache je Ort (eine Stunde), damit Tages- und Wochenplan nicht doppelt fragen. */
export class OpenMeteoProvider implements WeatherProvider {
  private readonly cache = new Map<string, { at: number; days: DayWeather[] }>();

  constructor(
    private readonly timezone: string,
    private readonly fetchImpl: typeof fetch = fetch,
    private readonly now: () => number = Date.now,
    private readonly cacheMs = 60 * 60 * 1000
  ) {}

  async forecast(location: GeoLocation, dates: readonly string[]): Promise<DayWeather[]> {
    const rounded = roundLocation(location);
    const key = `${rounded.latitude},${rounded.longitude}`;
    const cached = this.cache.get(key);
    let days: DayWeather[];
    if (cached !== undefined && this.now() - cached.at < this.cacheMs) {
      days = cached.days;
    } else {
      days = await this.fetchDays(rounded);
      this.cache.set(key, { at: this.now(), days });
    }
    return days.filter((day) => dates.includes(day.date));
  }

  private async fetchDays(location: GeoLocation): Promise<DayWeather[]> {
    const url = new URL("https://api.open-meteo.com/v1/forecast");
    url.searchParams.set("latitude", String(location.latitude));
    url.searchParams.set("longitude", String(location.longitude));
    url.searchParams.set("daily", DAILY.join(","));
    url.searchParams.set("timezone", this.timezone);
    url.searchParams.set("forecast_days", "14");
    const response = await this.fetchImpl(url, { signal: AbortSignal.timeout(5_000) });
    if (!response.ok) throw new Error(`Open-Meteo antwortete mit ${response.status}`);
    const body = (await response.json()) as { daily?: OpenMeteoDaily };
    const daily = body.daily;
    if (daily === undefined || !Array.isArray(daily.time)) throw new Error("Open-Meteo: keine Tageswerte");
    return daily.time.flatMap((date, index) => {
      const values = [daily.temperature_2m_max[index], daily.temperature_2m_min[index]];
      if (values.some((value) => typeof value !== "number")) return [];
      return [
        {
          date,
          temp_max_c: Math.round(daily.temperature_2m_max[index] as number),
          temp_min_c: Math.round(daily.temperature_2m_min[index] as number),
          precipitation_mm: Math.round((daily.precipitation_sum[index] ?? 0) * 10) / 10,
          precipitation_probability: Math.round(daily.precipitation_probability_max[index] ?? 0),
          wind_max_kmh: Math.round(daily.wind_speed_10m_max[index] ?? 0),
          weather_code: daily.weather_code[index] ?? 0
        }
      ];
    });
  }
}

/** Grenzen, ab denen draussen trainieren unsicher ist (Trainerpraxis, DWD-Warnstufen grob angelehnt). */
export const WEATHER_RULES = {
  heavyRainMm: 20,
  stormWindKmh: 60,
  hotTempC: 30,
  freezingTempC: 0
};

const THUNDERSTORM = new Set([95, 96, 99]);
const FREEZING_OR_SNOW = new Set([56, 57, 66, 67, 71, 73, 75, 77, 85, 86]);

/** Warum draussen heute nicht sicher ist (Gewitter, Starkregen, Sturm, Glaette), sonst `null`. Hitze zaehlt nicht dazu. */
export function severeWeather(day: DayWeather): string | null {
  if (THUNDERSTORM.has(day.weather_code)) return "Gewitter angesagt";
  if (day.wind_max_kmh >= WEATHER_RULES.stormWindKmh) return `Sturm angesagt (bis ${day.wind_max_kmh} km/h)`;
  if (day.precipitation_mm >= WEATHER_RULES.heavyRainMm) return `Starkregen angesagt (${day.precipitation_mm} mm)`;
  if (day.temp_min_c <= WEATHER_RULES.freezingTempC && (FREEZING_OR_SNOW.has(day.weather_code) || day.precipitation_mm >= 1)) return "Glätte möglich";
  return null;
}

const CODE_TEXT: Array<[number[], string]> = [
  [[0], "klar"],
  [[1, 2], "teils bewölkt"],
  [[3], "bedeckt"],
  [[45, 48], "Nebel"],
  [[51, 53, 55, 56, 57], "Niesel"],
  [[61, 63, 65, 80, 81, 82], "Regen"],
  [[66, 67], "gefrierender Regen"],
  [[71, 73, 75, 77, 85, 86], "Schnee"],
  [[95, 96, 99], "Gewitter"]
];

/** Lesbar fuer die Nutzernachricht: "8 bis 15 °C, Regen (80 %, 6 mm), Wind bis 30 km/h". */
export function weatherText(day: DayWeather): string {
  const kind = CODE_TEXT.find(([codes]) => codes.includes(day.weather_code))?.[1] ?? "wechselhaft";
  const rain = day.precipitation_mm > 0 || day.precipitation_probability >= 30 ? ` (${day.precipitation_probability} %, ${String(day.precipitation_mm).replace(".", ",")} mm)` : "";
  const heat = day.temp_max_c >= WEATHER_RULES.hotTempC ? ", heiß" : "";
  return `${day.temp_min_c} bis ${day.temp_max_c} °C, ${kind}${rain}, Wind bis ${day.wind_max_kmh} km/h${heat}`;
}
