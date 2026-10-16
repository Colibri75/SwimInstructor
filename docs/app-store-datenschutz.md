# App Store: Datenschutz-Angaben („App Privacy“)

Antworten für App Store Connect › App › **App-Datenschutz** (Nutzungsdaten-Etikett) und was dazu sonst eingetragen
werden muss. Grundlage ist, was App und Server tatsächlich tun (Datenschutzerklärung `backend/src/privacy/texts.ts`,
[plan-generation.md](plan-generation.md#datenschutz)). Ändert sich der Datenfluss, hier und in der Erklärung anpassen.

## Grunddaten

| Feld | Eintrag |
|---|---|
| Datenschutzrichtlinie-URL | `https://swiminstructor.kellner.v6.rocks/privacy` (Deutsch: `/datenschutz`) |
| Erfassen Sie oder Drittanbieter Daten aus dieser App? | **Ja** |
| Tracking (App Tracking Transparency) | **Nein**, keine Daten werden zum Tracking verwendet, kein ATT-Dialog nötig |
| Werbung, Analyse-SDKs, Crash-Reporter von Dritten | keine |

Apple zählt als „erfasst“, was das Gerät verlässt und länger gespeichert wird, als zum Beantworten der Anfrage in
Echtzeit nötig ist. Das trifft auf die Plananfragen zu: Anthropic hebt API-Anfragen eine begrenzte Zeit auf, der
Server den letzten Tagesplan und die Nutzungszahlen. Anthropic ist Auftragsverarbeiter („Service Provider“), seine
Verarbeitung gehört deshalb zu unseren Angaben und ist kein Tracking.

## Datentypen

Für jeden Typ gilt: **Zweck nur „App-Funktionalität“**, **nicht für Tracking**.

| Kategorie › Datentyp | Erfassen | Mit Identität verknüpft | Was genau |
|---|---|---|---|
| Gesundheit und Fitness › **Gesundheit** | Ja | Ja | Abweichung von Ruhepuls und HRV, Schlafdauer, Puls-Leistungswerte (Maximal-, Ruhe-, Schwellenpuls), Beschwerden mit Körperregion, gemeldete Krankheit/Verletzung, optional Körpergewicht |
| Gesundheit und Fitness › **Fitness** | Ja | Ja | Trainingsumfänge, Dauer, Strecken, Belastung, Tempo, gefühlte Anstrengung, Schwellenleistung/-tempo, Ziel, Wochenraster, Startniveau |
| Kontaktinformationen › **Name** | Ja | Ja | nur, wenn bei „Mit Apple anmelden“ freigegeben |
| Kontaktinformationen › **E-Mail-Adresse** | Ja | Ja | nur, wenn bei „Mit Apple anmelden“ freigegeben (auch Relay-Adresse) |
| Kennungen › **Benutzer-ID** | Ja | Ja | Apple-Nutzerkennung aus „Mit Apple anmelden“, interne Kontokennung |
| Nutzerinhalte › **Andere Nutzerinhalte** | Ja | Ja | Freitexte: Wünsche für den Tag, Feedback zum Gesamtplan, Notizen zum Wettkampftag |
| Standort › **Ungefährer Standort** | Ja | Nein | auf 0,1° (≈ 10 km) gerundeter Ort für das Wetter, nur mit „Wetter berücksichtigen“; der Server speichert ihn nicht und gibt nur die gerundeten Koordinaten an Open-Meteo weiter |
| Diagnose › **Andere Diagnosedaten** | Ja | Ja | Nutzungszahlen je Plananfrage (Kontokennung, Zeitpunkt, Plan-Art, Ergebnis, Token, Dauer), 120 Tage, für Kostenbremse und Fehlersuche |
| Andere Daten › **Andere Datentypen** | Ja | Ja | freie Minuten je Tag aus dem Kalender (ohne Termine), nur mit „Kalender berücksichtigen“; Ausrüstung |

**Nicht** erfassen (nicht ankreuzen): Finanzinfos, Genauer Standort, Sensible Infos, Kontakte, Fotos/Videos,
Audiodaten, Gameplay-Inhalte, Kundensupport, Browser- und Suchverlauf, Käufe, Produktinteraktion,
Werbedaten, Absturzdaten, Leistungsdaten, Geräte-ID, Telefonnummer, Postanschrift.

Hinweise zur Abgrenzung:

- Einzelne Health-Messwerte (Pulskurven, GPS-Routen der Watch), Geburtsdatum und Kalendertermine verlassen das Gerät
  nicht und werden deshalb nicht angegeben.
- IP-Adressen in den Server-Protokollen gelten bei Apple nicht als eigener Datentyp, solange sie nicht für Standort
  oder Tracking genutzt werden; sie stehen in der Datenschutzerklärung.
- Wenn „Mit Apple anmelden“ zum Release nicht live ist (nur Token), entfallen Name, E-Mail-Adresse und die
  Apple-Nutzerkennung; „Benutzer-ID“ bleibt wegen der Kontokennung.

## Weitere Punkte für die Prüfung

- **Richtlinie 5.1.2(i)** (Weitergabe an Dritt-KI): Vor der ersten Plananfrage fragt die App ausdrücklich um
  Zustimmung, nennt Anthropic als Empfänger und verlinkt die Erklärung (Einrichtung, sonst als Blatt vor der ersten
  Anfrage). Ohne Zustimmung geht keine Plananfrage hinaus (`PlanAPIClient.post`, `AIDataConsent`). Widerruf unter
  Einstellungen › Datenschutz. In den Notes for Review kurz erwähnen, wo der Dialog erscheint.
- **Richtlinie 5.1.3** (HealthKit): Health-Daten nur für die Pläne, nie Werbung, nie verkauft, nicht in iCloud. Steht
  so in der Erklärung, Abschnitt 7.
- **Richtlinie 5.1.1(v)** (Konto löschen): Mit „Mit Apple anmelden“ muss das Konto in der App löschbar sein; die
  Erklärung beschreibt das.
- Die Datenschutz-URL zusätzlich in der App verlinkt: Einstellungen › Datenschutz › Datenschutzerklärung.
