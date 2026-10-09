/**
 * Die Datenschutzerklaerung der App, auf Deutsch (`/datenschutz`) und Englisch (`/privacy`). Platzhalter in doppelten
 * geschweiften Klammern fuellt `renderPrivacyPolicy` aus der Konfiguration (PRIVACY_CONTACT_*, PRIVACY_HOSTER).
 *
 * Was hier steht, muss zu dem passen, was App und Server tatsaechlich tun (docs/plan-generation.md, "Datenschutz").
 * Aendert sich, was an den Server oder an Anthropic geht, hier anpassen, `PRIVACY_POLICY_DATE` setzen und in der App
 * `AIDataConsentStore.currentVersion` erhoehen, damit alle neu zustimmen.
 */
export const PRIVACY_POLICY_DATE = { de: "9. Oktober 2026", en: "9 October 2026" };

export const POLICY_DE = `
<h1>Datenschutzerklärung für die App Peaksmith</h1>
<p class="meta">Stand: {{STAND}}</p>

<h2>1. Verantwortlicher</h2>
<p>{{NAME}}<br>{{ANSCHRIFT}}<br>E-Mail: {{EMAIL}}</p>
<p>Peaksmith wird von einer Privatperson entwickelt und betrieben. Ein Datenschutzbeauftragter ist nicht bestellt.
Bei Fragen zum Datenschutz und für alle Anträge zu deinen Rechten genügt eine E-Mail an die oben genannte Adresse.</p>

<h2>2. Kurz gesagt</h2>
<ul>
  <li>Peaksmith erstellt Trainingspläne für Schwimmen, Radfahren und Laufen. Die meisten Daten bleiben auf deinem
  iPhone und deiner Apple Watch.</li>
  <li>Für einen Plan schickt die App eine Zusammenfassung deines Trainings- und Erholungszustands an unseren Server.
  Der Server lässt den Plan vom KI-Modell Claude der Firma Anthropic PBC (USA) erstellen. Das passiert erst, nachdem
  du in der App ausdrücklich zugestimmt hast.</li>
  <li>Keine Werbung, kein Tracking, keine Analyse- oder Absturz-Dienste von Dritten, kein Verkauf von Daten.</li>
</ul>

<h2>3. Daten, die nur auf deinem Gerät verarbeitet werden</h2>
<ul>
  <li><strong>Apple Health (HealthKit):</strong> Mit deiner Erlaubnis liest die App Trainings (Sportart, Datum, Dauer,
  Strecke, Energie, Herzfrequenz, Schwimmzüge, Leistung und Trittfrequenz beim Radfahren), Ruhepuls,
  Herzfrequenzvariabilität (HRV), Schlaf und dein Geburtsdatum (nur, um deinen Maximalpuls zu schätzen). Mit der
  Apple Watch aufgezeichnete Trainings, samt Herzfrequenz und bei Training im Freien der Strecke (GPS), speichert die
  App in Apple Health. Diese Einzelwerte verlassen dein Gerät nicht.</li>
  <li><strong>Kalender</strong> (nur, wenn du „Kalender berücksichtigen“ einschaltest): Die App liest, wann du Termine
  hast, und berechnet daraus deine freie Zeit. Titel, Orte und Teilnehmer der Termine bleiben auf dem iPhone.</li>
  <li><strong>Standort</strong> (nur, wenn du „Wetter berücksichtigen“ einschaltest): Die App bestimmt deinen
  ungefähren Ort und rundet ihn auf dem Gerät auf etwa 10 km.</li>
  <li><strong>Einstellungen und Inhalte der App:</strong> Ziel, Wochenraster, Startniveau, Leistungswerte,
  Rückmeldungen zu Einheiten, Wünsche und die erhaltenen Pläne liegen im Speicher der App auf dem iPhone und werden
  für Widgets und die Apple Watch zwischen App, Widgets und Watch geteilt. Dein Zugangsschlüssel zum Server liegt im
  Schlüsselbund des iPhones.</li>
  <li><strong>Mitteilungen</strong> plant die App lokal auf dem Gerät. Es gibt keinen Push-Dienst und keine
  Push-Kennung.</li>
</ul>

<h2>4. Daten, die an unseren Server gehen</h2>
<h3>a) Dein Konto</h3>
<p>Wenn du dich mit „Mit Apple anmelden“ anmeldest, speichert der Server die von Apple vergebene, nur für diese App
gültige Nutzerkennung und, falls du sie bei der Anmeldung freigibst, deine E-Mail-Adresse (auch Apples anonyme
Weiterleitungsadresse) und deinen Namen. Dazu kommt ein Zugangsschlüssel, mit dem die App ihre Anfragen
ausweist.</p>

<h3>b) Anfragen für einen Plan (nur mit deiner Einwilligung)</h3>
<ul>
  <li><strong>Zusammenfassung deines Zustands:</strong> Trainingsumfänge, Anzahl, Dauer und Strecke der Einheiten,
  Belastung und Tage seit der letzten Einheit je Sportart, Tempo-Entwicklung; Erholungswerte als Abweichung von deinem
  Normalwert (Ruhepuls, HRV) und deine durchschnittliche Schlafdauer; Leistungswerte und Trainingszonen (Maximal-,
  Ruhe- und Schwellenpuls, Schwellenleistung, Schwellentempo); dein Ziel (Art, Strecke, Zielzeit, Datum),
  Wochenraster und selbst angegebenes Startniveau.</li>
  <li><strong>Training der letzten Tage</strong> je Einheit: Datum, Sportart, Dauer, Strecke, ob sie hart war,
  gefühlte Anstrengung, Beschwerden (Stärke und Körperregion) und verpasste Einheiten.</li>
  <li><strong>Was du selbst eingibst:</strong> Wünsche für den Tag, Rückmeldungen zum Gesamtplan, Notizen und
  Startzeit für den Wettkampftag, gemeldete Pausen (krank, verletzt, Urlaub), auf Wunsch dein Körpergewicht für die
  Verpflegung am Wettkampftag.</li>
  <li><strong>Einstellungen:</strong> deine Ausrüstung, Kraft- und Mobilitätstraining, Leistungstests, die Sprache der
  App.</li>
  <li>Wenn eingeschaltet: deinen auf etwa 10 km gerundeten Ort (für die Wettervorhersage) und deine freie Zeit je Tag
  in Minuten (aus dem Kalender, ohne Termine).</li>
</ul>
<p>Nicht übertragen werden einzelne Messwerte aus Apple Health (z. B. Herzfrequenzkurven oder GPS-Strecken),
Kalendertermine und dein Geburtsdatum. Ruhepuls, HRV, Schlaf, Pulswerte, Beschwerden, Krankheit, Verletzung und
Körpergewicht sind <strong>Gesundheitsdaten</strong> im Sinne von Art. 9 DSGVO.</p>

<h3>c) Technische Daten</h3>
<p>Bei jedem Aufruf des Servers entstehen Protokolleinträge mit IP-Adresse, Zeitpunkt, aufgerufener Adresse,
Statuscode, Dauer und der Kennung von App und Betriebssystem (User-Agent). Für jede Plananfrage speichert der Server
außerdem Nutzungszahlen: deine interne Nutzerkennung, Zeitpunkt, Art des Plans, Ergebnis, Modell, Umfang der
KI-Anfrage (Token), Dauer und geschätzte Kosten, ohne Trainings- oder Gesundheitsdaten.</p>

<h2>5. Zwecke und Rechtsgrundlagen</h2>
<ul>
  <li><strong>Pläne erstellen und die App bereitstellen</strong> (Konto, Plananfragen, Speicherung des letzten
  Plans): Art. 6 Abs. 1 lit. b DSGVO (Nutzungsvertrag über die App).</li>
  <li><strong>Gesundheitsdaten</strong> verarbeiten wir und geben sie an Anthropic weiter nur mit deiner
  <strong>ausdrücklichen Einwilligung</strong> nach Art. 9 Abs. 2 lit. a DSGVO (zusammen mit Art. 6 Abs. 1 lit. a
  DSGVO). Die App fragt dich vor der ersten Anfrage. Du kannst die Einwilligung jederzeit in der App unter
  Einstellungen › Datenschutz widerrufen; danach schickt die App keine Plananfragen mehr. Der Widerruf gilt für die
  Zukunft, die Verarbeitung bis dahin bleibt rechtmäßig (Art. 7 Abs. 3 DSGVO).</li>
  <li><strong>Server-Protokolle und Nutzungszahlen</strong> (Betrieb, Sicherheit, Fehlersuche, Begrenzung von
  Missbrauch und Kosten): Art. 6 Abs. 1 lit. f DSGVO. Unser berechtigtes Interesse ist ein sicherer und bezahlbarer
  Betrieb.</li>
</ul>
<p>Die Bereitstellung der Daten ist freiwillig. Ohne Einwilligung kannst du die App weiter nutzen (z. B. Training
aufzeichnen und Statistiken ansehen), bekommst aber keine neuen Pläne. Die Pläne entstehen automatisch, haben aber
keine rechtliche oder ähnlich erhebliche Wirkung für dich (keine Entscheidung im Sinne von Art. 22 DSGVO); sie sind
Vorschläge, die du jederzeit ändern oder ignorieren kannst.</p>

<h2>6. Empfänger</h2>
<ul>
  <li><strong>Anthropic PBC</strong>, 548 Market Street, PMB 90375, San Francisco, CA 94104, USA, als
  Auftragsverarbeiter (Art. 28 DSGVO) für die Erstellung der Pläne mit dem KI-Modell Claude. Anthropic bekommt die
  unter 4 b) genannten Daten ohne deinen Namen, deine E-Mail-Adresse oder deine Nutzerkennung. Nach den geschäftlichen
  Bedingungen von Anthropic werden Eingaben und Ausgaben der Schnittstelle nicht zum Training von KI-Modellen
  verwendet und nur begrenzte Zeit gespeichert (Einzelheiten:
  <a href="https://www.anthropic.com/legal/privacy">anthropic.com/legal/privacy</a>).<br>
  <em>Übermittlung in die USA:</em> Die USA sind ein Drittland. Die Übermittlung stützt sich auf den
  Angemessenheitsbeschluss der EU-Kommission zum EU-US Data Privacy Framework (Art. 45 DSGVO), soweit der Empfänger
  danach zertifiziert ist, und im Übrigen auf die Standardvertragsklauseln der EU-Kommission (Art. 46 Abs. 2 lit. c
  DSGVO), die Teil der Vereinbarung zur Auftragsverarbeitung mit Anthropic sind. Eine Kopie der Garantien bekommst du
  auf Anfrage.</li>
  <li><strong>Hosting:</strong> Der Server läuft auf einem gemieteten virtuellen Server bei {{HOSTER}}, der als
  Auftragsverarbeiter tätig ist. Den Server selbst verwalten wir.</li>
  <li><strong>Wettervorhersage:</strong> Mit eingeschaltetem Wetter fragt unser Server bei Open-Meteo
  (open-meteo.com) die Vorhersage für den gerundeten Ort ab. Dabei gehen nur die gerundeten Koordinaten an
  Open-Meteo, nicht deine IP-Adresse oder andere Angaben zu dir.</li>
  <li><strong>Apple:</strong> Für „Mit Apple anmelden“, Apple Health und den App Store gelten die
  Datenschutzbestimmungen von Apple. Apple ist für diese Dienste selbst verantwortlich.</li>
</ul>
<p>Darüber hinaus geben wir keine Daten weiter, verkaufen keine Daten und nutzen sie nicht für Werbung.</p>

<h2>7. Apple Health (HealthKit)</h2>
<p>Daten aus Apple Health nutzen wir ausschließlich, um deine Trainingspläne zu erstellen und dir dein Training
anzuzeigen. Sie werden <strong>nie für Werbung oder Marketing genutzt, nie verkauft</strong> und nie an
Werbenetzwerke, Datenhändler oder andere Dritte weitergegeben, außer wie oben beschrieben an Anthropic zur Erstellung
deines Plans und nur mit deiner Einwilligung. Die App speichert Health-Daten nicht in iCloud.</p>

<h2>8. Speicherdauer</h2>
<ul>
  <li><strong>Plananfragen</strong> (Zusammenfassung, Training, deine Eingaben) verarbeitet der Server nur, solange
  die Anfrage läuft, und speichert sie nicht.</li>
  <li><strong>Letzter Tagesplan:</strong> Der Server hebt je Konto den zuletzt erstellten Tagesplan als Ersatz für
  Ausfälle auf. Er kann Hinweise des Coaches auf deine Werte enthalten und wird durch jeden neuen Plan ersetzt.</li>
  <li><strong>Kontodaten</strong> und der letzte Tagesplan bleiben, bis du dein Konto löschst. Das geht in der App;
  dabei löschen wir die zu deinem Konto gespeicherten Daten auf dem Server.</li>
  <li><strong>Nutzungszahlen</strong> werden nach 120 Tagen gelöscht.</li>
  <li><strong>Server-Protokolle</strong> werden laufend überschrieben; gesicherte Protokolle löschen wir nach 30
  Tagen.</li>
  <li><strong>Sicherungskopien</strong> des Servers werden nach 14 Tagen gelöscht. Daten eines gelöschten Kontos
  verschwinden damit spätestens 14 Tage nach der Löschung auch aus den Sicherungen.</li>
  <li><strong>Bei Anthropic</strong> gelten die Fristen von Anthropic (siehe 6).</li>
  <li><strong>Auf deinem Gerät</strong> bleiben die Daten, bis du sie in der App änderst oder die App löschst.
  Daten in Apple Health verwaltest du in der Health-App.</li>
</ul>

<h2>9. Deine Rechte</h2>
<p>Du hast das Recht auf Auskunft (Art. 15 DSGVO), Berichtigung (Art. 16), Löschung (Art. 17), Einschränkung der
Verarbeitung (Art. 18) und Datenübertragbarkeit (Art. 20). Einer Verarbeitung auf Grundlage von Art. 6 Abs. 1 lit. f
DSGVO kannst du aus Gründen, die sich aus deiner besonderen Situation ergeben, widersprechen (Art. 21). Eine
Einwilligung kannst du jederzeit mit Wirkung für die Zukunft widerrufen (Art. 7 Abs. 3), in der App unter
Einstellungen › Datenschutz oder per E-Mail. Dein Konto und die Daten auf dem Server kannst du in der App löschen.</p>
<p>Du hast außerdem das Recht, dich bei einer Datenschutz-Aufsichtsbehörde zu beschweren (Art. 77 DSGVO), etwa bei
der Behörde deines Wohnorts oder der des Verantwortlichen.</p>

<h2>10. Kein Tracking, keine Cookies</h2>
<p>Die App enthält keine Werbung, keine Tracking- oder Analyse-Werkzeuge und keine Software von Dritten, die Daten
über dich sammelt. Wir verknüpfen keine Daten mit Daten anderer Apps oder Websites. Diese Seite setzt keine Cookies
und lädt nichts von anderen Servern.</p>

<h2>11. Sicherheit</h2>
<p>Die Verbindung zwischen App und Server ist verschlüsselt (HTTPS). Jede Anfrage braucht einen persönlichen
Zugangsschlüssel. Der Server ist nur über HTTPS erreichbar, und nur der Betreiber hat Zugriff.</p>

<h2>12. Kinder</h2>
<p>Die App richtet sich an Personen ab 16 Jahren.</p>

<h2>13. Änderungen</h2>
<p>Ändert sich, welche Daten die App weitergibt, passen wir diese Erklärung an und bitten dich in der App erneut um
deine Einwilligung. Es gilt die jeweils hier veröffentlichte Fassung.</p>

<p class="meta"><a href="/privacy" hreflang="en">English version</a></p>
`;

export const POLICY_EN = `
<h1>Privacy Policy for the Peaksmith app</h1>
<p class="meta">Last updated: {{STAND}}</p>
<p class="meta">This is a translation. In case of doubt, the <a href="/datenschutz" hreflang="de">German version</a>
prevails.</p>

<h2>1. Controller</h2>
<p>{{NAME}}<br>{{ANSCHRIFT}}<br>Email: {{EMAIL}}</p>
<p>Peaksmith is developed and operated by a private individual in Germany. No data protection officer has been
appointed. For any privacy question and to exercise your rights, simply send an email to the address above.</p>

<h2>2. In short</h2>
<ul>
  <li>Peaksmith creates training plans for swimming, cycling and running. Most data stays on your iPhone and Apple
  Watch.</li>
  <li>To create a plan, the app sends a summary of your training and recovery status to our server. The server has
  the plan created by the AI model Claude from Anthropic PBC (USA). This only happens after you have explicitly agreed
  in the app.</li>
  <li>No advertising, no tracking, no third-party analytics or crash reporting, no sale of data.</li>
</ul>

<h2>3. Data processed only on your device</h2>
<ul>
  <li><strong>Apple Health (HealthKit):</strong> With your permission, the app reads workouts (sport, date, duration,
  distance, energy, heart rate, swim strokes, cycling power and cadence), resting heart rate, heart rate variability
  (HRV), sleep and your date of birth (only to estimate your maximum heart rate). Workouts recorded with the Apple
  Watch, including heart rate and, for outdoor workouts, the route (GPS), are saved to Apple Health. These individual
  values never leave your device.</li>
  <li><strong>Calendar</strong> (only if you turn on “Consider calendar”): the app reads when you have events and
  calculates your free time. Titles, locations and attendees of your events stay on the iPhone.</li>
  <li><strong>Location</strong> (only if you turn on “Consider weather”): the app determines your approximate location
  and rounds it on the device to about 10 km.</li>
  <li><strong>App settings and content:</strong> goal, weekly schedule, starting level, performance values, feedback
  on sessions, wishes and the plans you received are stored in the app's storage on the iPhone and shared between the
  app, its widgets and the Apple Watch. Your access key for the server is stored in the iPhone's keychain.</li>
  <li><strong>Notifications</strong> are scheduled locally on the device. There is no push service and no push
  token.</li>
</ul>

<h2>4. Data sent to our server</h2>
<h3>a) Your account</h3>
<p>If you use “Sign in with Apple”, the server stores the user identifier Apple issues for this app and, if you share
them when signing in, your email address (including Apple's private relay address) and your name. In addition, an
access key identifies the app's requests.</p>

<h3>b) Plan requests (only with your consent)</h3>
<ul>
  <li><strong>Summary of your status:</strong> training volumes, number, duration and distance of sessions, load and
  days since the last session per sport, pace trend; recovery values as deviation from your normal (resting heart
  rate, HRV) and your average sleep duration; performance values and training zones (maximum, resting and threshold
  heart rate, threshold power, threshold pace); your goal (type, distance, target time, date), weekly schedule and
  self-reported starting level.</li>
  <li><strong>Recent training</strong> per session: date, sport, duration, distance, whether it was hard, perceived
  effort, discomfort (severity and body region) and missed sessions.</li>
  <li><strong>What you enter yourself:</strong> wishes for the day, feedback on the overall plan, notes and start time
  for race day, reported breaks (illness, injury, vacation) and, if you choose, your body weight for race-day
  nutrition.</li>
  <li><strong>Settings:</strong> your equipment, strength and mobility training, performance tests, the app
  language.</li>
  <li>If turned on: your location rounded to about 10 km (for the weather forecast) and your free time per day in
  minutes (from the calendar, without events).</li>
</ul>
<p>Individual readings from Apple Health (e.g. heart rate curves or GPS routes), calendar events and your date of
birth are not transmitted. Resting heart rate, HRV, sleep, heart rate values, discomfort, illness, injury and body
weight are <strong>health data</strong> within the meaning of Art. 9 GDPR.</p>

<h3>c) Technical data</h3>
<p>Each request to the server creates log entries with IP address, time, requested path, status code, duration and
the app and operating system identifier (user agent). For each plan request, the server also stores usage figures:
your internal user identifier, time, plan type, result, model, size of the AI request (tokens), duration and
estimated cost, without any training or health data.</p>

<h2>5. Purposes and legal bases</h2>
<ul>
  <li><strong>Creating plans and providing the app</strong> (account, plan requests, storing the latest plan):
  Art. 6(1)(b) GDPR (contract for the use of the app).</li>
  <li>We process <strong>health data</strong> and share it with Anthropic only with your <strong>explicit
  consent</strong> under Art. 9(2)(a) GDPR (together with Art. 6(1)(a) GDPR). The app asks you before the first
  request. You can withdraw your consent at any time in the app under Settings › Privacy; the app then stops sending
  plan requests. Withdrawal applies to the future; processing until then remains lawful (Art. 7(3) GDPR).</li>
  <li><strong>Server logs and usage figures</strong> (operation, security, troubleshooting, limiting abuse and cost):
  Art. 6(1)(f) GDPR. Our legitimate interest is secure and affordable operation.</li>
</ul>
<p>Providing data is voluntary. Without consent you can still use the app (e.g. record workouts and view statistics),
but you will not receive new plans. Plans are generated automatically but have no legal or similarly significant
effect on you (no decision within the meaning of Art. 22 GDPR); they are suggestions you can change or ignore at any
time.</p>

<h2>6. Recipients</h2>
<ul>
  <li><strong>Anthropic PBC</strong>, 548 Market Street, PMB 90375, San Francisco, CA 94104, USA, as processor
  (Art. 28 GDPR) for creating plans with the AI model Claude. Anthropic receives the data listed in 4 b) without your
  name, email address or user identifier. Under Anthropic's commercial terms, inputs and outputs of the API are not
  used to train AI models and are retained only for a limited time (details:
  <a href="https://www.anthropic.com/legal/privacy">anthropic.com/legal/privacy</a>).<br>
  <em>Transfer to the USA:</em> The USA is a third country. The transfer is based on the European Commission's
  adequacy decision for the EU-US Data Privacy Framework (Art. 45 GDPR) to the extent the recipient is certified under
  it, and otherwise on the European Commission's Standard Contractual Clauses (Art. 46(2)(c) GDPR), which are part of
  the data processing agreement with Anthropic. You can request a copy of these safeguards.</li>
  <li><strong>Hosting:</strong> The server runs on a rented virtual server at {{HOSTER}}, acting as processor. We
  administer the server ourselves.</li>
  <li><strong>Weather forecast:</strong> With weather turned on, our server requests the forecast for the rounded
  location from Open-Meteo (open-meteo.com). Only the rounded coordinates are sent to Open-Meteo, not your IP address
  or any other information about you.</li>
  <li><strong>Apple:</strong> Apple's privacy policy applies to Sign in with Apple, Apple Health and the App Store.
  Apple is itself responsible for these services.</li>
</ul>
<p>We do not share data with anyone else, do not sell data and do not use it for advertising.</p>

<h2>7. Apple Health (HealthKit)</h2>
<p>We use data from Apple Health exclusively to create your training plans and to show you your training. It is
<strong>never used for advertising or marketing, never sold</strong> and never shared with advertising networks, data
brokers or other third parties, except with Anthropic as described above to create your plan, and only with your
consent. The app does not store health data in iCloud.</p>

<h2>8. Retention</h2>
<ul>
  <li><strong>Plan requests</strong> (summary, training, your input) are processed by the server only while the
  request is running and are not stored.</li>
  <li><strong>Latest day plan:</strong> per account, the server keeps the most recently created day plan as a
  fallback for outages. It may contain coaching notes referring to your values and is replaced by each new plan.</li>
  <li><strong>Account data</strong> and the latest day plan are kept until you delete your account. You can do this in
  the app; we then delete the data stored for your account on the server.</li>
  <li><strong>Usage figures</strong> are deleted after 120 days.</li>
  <li><strong>Server logs</strong> are continuously overwritten; archived logs are deleted after 30 days.</li>
  <li><strong>Server backups</strong> are deleted after 14 days, so data of a deleted account disappears from backups
  no later than 14 days after deletion.</li>
  <li><strong>At Anthropic</strong>, Anthropic's retention periods apply (see 6).</li>
  <li><strong>On your device</strong>, data stays until you change it in the app or delete the app. You manage data in
  Apple Health in the Health app.</li>
</ul>

<h2>9. Your rights</h2>
<p>You have the right of access (Art. 15 GDPR), rectification (Art. 16), erasure (Art. 17), restriction of
processing (Art. 18) and data portability (Art. 20). You may object to processing based on Art. 6(1)(f) GDPR on
grounds relating to your particular situation (Art. 21). You can withdraw consent at any time with effect for the
future (Art. 7(3)), in the app under Settings › Privacy or by email. You can delete your account and the data on the
server in the app.</p>
<p>You also have the right to lodge a complaint with a data protection supervisory authority (Art. 77 GDPR), for
example the authority where you live or where the controller is located.</p>

<h2>10. No tracking, no cookies</h2>
<p>The app contains no advertising, no tracking or analytics tools and no third-party software that collects data
about you. We do not link data with data from other apps or websites. This page sets no cookies and loads nothing from
other servers.</p>

<h2>11. Security</h2>
<p>The connection between the app and the server is encrypted (HTTPS). Every request requires a personal access key.
The server is only reachable via HTTPS, and only the operator has access.</p>

<h2>12. Children</h2>
<p>The app is intended for people aged 16 and over.</p>

<h2>13. Changes</h2>
<p>If the data the app shares changes, we will update this policy and ask for your consent again in the app. The
version published here applies.</p>

<p class="meta"><a href="/datenschutz" hreflang="de">Deutsche Fassung</a></p>
`;
