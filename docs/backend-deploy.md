# Backend auf dem Server einrichten (Docker + Caddy)

Das Backend läuft als Docker-Container und veröffentlicht seinen Port nur auf `127.0.0.1:3100`
des Servers, genau wie deine anderen Dienste (Vaultwarden, Immich, Financial-App). Dein
bestehender **Caddy** (läuft im Container) nimmt die Anfragen von außen an, kümmert sich um
HTTPS und leitet sie an den Container weiter. Die anderen Dienste bleiben unangetastet: Du
ergänzt nur einen Block in der Caddyfile.

Die Befehle laufen als `root` auf dem Server (sonst `sudo` davorsetzen). `docker compose` liest
die Konfigurationsdatei als aufrufender Nutzer, deshalb auch die Deploys als root ausführen.

Die API bekommt den Hostnamen **`swiminstructor.kellner.v6.rocks`**.

## Voraussetzungen prüfen

```bash
docker compose version                        # Compose vorhanden
ss -tlnp | grep ':3100 '                      # liefert nichts: Port ist frei
docker inspect caddy --format '{{.HostConfig.NetworkMode}}'   # soll "host" ausgeben
```

Die letzte Zeile ist wichtig: Nur mit Host-Netzwerk erreicht Caddy den Backend-Container über
`127.0.0.1:3100`. Steht dort etwas anderes, hör hier auf und melde dich, dann ändere ich die
Anbindung.

Außerdem muss der Hostname auf deinen Server zeigen. Prüfe das von deinem Rechner oder vom
Server aus:

```bash
dig +short A    swiminstructor.kellner.v6.rocks   # soll 144.91.69.144 zeigen
dig +short AAAA swiminstructor.kellner.v6.rocks   # falls vorhanden: die IPv6-Adresse des Servers
```

Kommt bei `A` nichts zurück, ist im DynDNS-Eintrag keine IPv4-Adresse hinterlegt. Trag dort
`144.91.69.144` ein, sonst kann Caddy kein Zertifikat holen und iPhones im Mobilfunknetz
erreichen die API womöglich nicht.

## 1. Code auf den Server holen

Ein GitHub-Token (PAT) mit Lesezugriff auf das Repo wird gebraucht, weil das Repo privat ist.

```bash
mkdir -p /opt/stack
git clone https://github.com/Colibri75/SwimInstructor.git /opt/stack/swiminstructor
# Benutzername: Colibri75, Passwort: dein PAT (kein GitHub-Passwort)
```

## 2. Geheimen Token und Konfiguration anlegen

```bash
mkdir -p /etc/swiminstructor
TOKEN=$(openssl rand -hex 32)
printf 'API_TOKEN=%s\n' "$TOKEN" > /etc/swiminstructor/backend.env
chmod 600 /etc/swiminstructor/backend.env
echo "Dein API-Token (jetzt sicher notieren, die App braucht ihn später):"
echo "$TOKEN"
```

Der Token steht danach nur in dieser Datei (lesbar nur für root). Er gehört später in die App
und nie in das Repo. Die übrigen Einstellungen (Port, Produktionsmodus) stehen in
`backend/compose.yaml`.

## 3. Container starten

```bash
cd /opt/stack/swiminstructor/backend
docker compose up -d --build
docker compose ps                 # Status sollte "healthy" werden (nach ca. 5-10 s)
curl -s http://127.0.0.1:3100/health
# {"status":"ok","uptimeSeconds":3}
```

Der erste Build dauert ein bis zwei Minuten. Läuft der Container nicht:
`docker logs swiminstructor-backend`.

## 4. Caddy einrichten

Finde zuerst heraus, wo die Caddyfile auf dem Server liegt:

```bash
docker inspect caddy --format '{{json .Mounts}}'
```

In der Ausgabe siehst du unter `Source` den Pfad auf dem Server und unter `Destination` den Pfad
im Container (meist `/etc/caddy/Caddyfile`, bei einem Ordner-Mount liegt sie darin).

Ergänze in der Caddyfile auf dem Server den Block aus `backend/deploy/Caddyfile.example` (als
eigenen Block, die bestehenden lässt du stehen). Dann erst prüfen, danach laden. Das Laden geht
ohne Ausfall, die anderen Dienste merken nichts:

```bash
docker exec caddy caddy validate --config /etc/caddy/Caddyfile     # muss "Valid configuration" melden
docker exec caddy caddy reload   --config /etc/caddy/Caddyfile
docker logs --tail 30 caddy                                        # Zertifikat wird geholt
```

Nimm bei `--config` den `Destination`-Pfad aus dem Inspect. Meldet die Prüfung einen Fehler,
lädst du nicht neu, dann läuft alles unverändert weiter.

Ändert sich der Block in `Caddyfile.example` später (zuletzt `response_header_timeout` von 90 s auf
240 s, weil ein Gesamtplan länger dauert), übernimmst du die Änderung genauso: Caddyfile auf dem Server
anpassen, prüfen, neu laden.

## 5. Prüfen (das ist die Definition of Done von M4)

Von deinem Rechner aus, nicht vom Server:

```bash
curl -i https://swiminstructor.kellner.v6.rocks/health
# HTTP/2 200 ... {"status":"ok",...}

curl -i https://swiminstructor.kellner.v6.rocks/v1/status
# HTTP/2 401 ... {"error":"unauthorized"}

curl -i -H "Authorization: Bearer <DEIN-TOKEN>" https://swiminstructor.kellner.v6.rocks/v1/status
# HTTP/2 200 ... {"status":"authenticated","user":"owner"}
```

Der Token-Test auf einem Windows-Rechner (PowerShell, `curl.exe` mit Endung). Der Token wird
beim Einfügen nicht angezeigt:

```powershell
$s = Read-Host -AsSecureString -Prompt "Token"
$t = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
curl.exe -i -H "Authorization: Bearer $t" https://swiminstructor.kellner.v6.rocks/v1/status
Remove-Variable s, t
```

Im Browser muss beim Aufruf von `https://swiminstructor.kellner.v6.rocks/health` ein gültiges
Schloss erscheinen (keine Zertifikatswarnung). Prüfe außerdem, dass deine anderen Dienste (Financial,
Vaultwarden, Immich, Nextcloud) weiter normal erreichbar sind.

Und von außen darf der Container-Port nicht direkt offen sein:

```bash
curl -m 5 http://144.91.69.144:3100/health      # muss fehlschlagen (Timeout/Connection refused)
```

## Claude-API-Key einrichten (ab M5)

Der Plan-Endpunkt `POST /v1/plan/today` braucht einen Anthropic-API-Key. Ohne Key läuft der Server
weiter, der Endpunkt liefert dann nur gespeicherte Pläne (oder `503`).

1. Lege in der [Anthropic Console](https://console.anthropic.com) einen API-Key an. Er ist ein
   eigenes Produkt, getrennt von einem claude.ai-Abo, und wird pro Token abgerechnet.
2. Setze dort unter *Limits* ein monatliches Ausgabenlimit (Kosten siehe
   [plan-generation.md](plan-generation.md)).
3. Trage den Key auf dem Server ein. `read -s` zeigt ihn beim Einfügen nicht an:

```bash
read -s -p "Anthropic API-Key: " KEY; echo
printf 'ANTHROPIC_API_KEY=%s\n' "$KEY" >> /etc/swiminstructor/backend.env
unset KEY
cd /opt/stack/swiminstructor/backend && docker compose up -d --force-recreate
```

4. Prüfe, dass der Key ankommt: `docker logs swiminstructor-backend` zeigt beim Start keine Warnung
   "ANTHROPIC_API_KEY nicht gesetzt" mehr.

Der letzte Plan liegt im Docker-Volume `swim_data` (`/data` im Container) und übersteht
Neustarts und Updates. Weitere Einstellungen (`PLAN_MODEL`, `PLAN_EFFORT`, Kostenbremse)
stehen in [plan-generation.md](plan-generation.md) und lassen sich in derselben Datei
`/etc/swiminstructor/backend.env` setzen.

## Hinweis zum Zertifikat

`v6.rocks` ist eine gemeinsame DynDNS-Domain. Let's Encrypt begrenzt neue Zertifikate pro Domain
(50 pro Woche), und dieses Limit ist dort oft ausgeschöpft. Im Caddy-Log steht dann `HTTP 429 ...
rateLimited`. Das ist unkritisch: Caddy weicht automatisch auf ZeroSSL aus und holt das
Zertifikat dort (`certificate obtained successfully`). Es ist genauso gültig. Die Ausstellung
dauert dann nur etwa eine Minute länger, und ein Aufruf in dieser Zeit schlägt fehl.

## Aktualisieren

Nach jedem Merge, der das Backend ändert:

```bash
/opt/stack/swiminstructor/backend/deploy/deploy.sh
```

Das Skript holt den neuesten Stand aus `main`, baut das Image, startet den Container neu und
wartet auf den Healthcheck. Wird der neue Container nicht gesund, startet es wieder das vorige Image
(`swiminstructor-backend:previous`), meldet das deutlich und endet mit Fehler. Der Server läuft dann weiter
in der alten Version, bis du den Fehler behoben hast.

### Automatisch deployen (optional)

Der Workflow `Backend Deploy` spielt das Backend nach jedem grünen `Backend CI` auf `main` selbst ein. Er
bleibt aus, solange die Secrets fehlen. GitHub meldet sich als root an, der Schlüssel kann aber nur
`deploy.sh` starten. Einrichtung, einmalig, als root auf dem Server:

1. Einen eigenen Schlüssel nur für dieses Repo anlegen und ihn auf das Skript festnageln:

```bash
ssh-keygen -t ed25519 -N "" -C github-swiminstructor -f /root/gh-swiminstructor
echo "command=\"/opt/stack/swiminstructor/backend/deploy/deploy.sh\",no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty $(cat /root/gh-swiminstructor.pub)" >> /root/.ssh/authorized_keys
sshd -T | grep -i permitrootlogin   # muss yes, prohibit-password oder forced-commands-only sein, nicht no
```

2. Testen, ob der Schlüssel das Deployment auslöst (deployt einmal den aktuellen Stand):

```bash
ssh -i /root/gh-swiminstructor -o IdentitiesOnly=yes root@localhost   # endet mit "Deploy erfolgreich"
```

3. Die Werte für GitHub auslesen und unter *Settings → Secrets and variables → Actions → New repository
   secret* eintragen:
   - `DEPLOY_HOST`: der Name, unter dem GitHub den Server per SSH erreicht (IPv4 nötig, GitHub-Runner
     haben kein IPv6).
   - `DEPLOY_USER`: `root`
   - `DEPLOY_PORT`: nur nötig, wenn SSH nicht auf Port 22 läuft (`sshd -T | grep -i '^port'` zeigt den Port).
   - `DEPLOY_SSH_KEY`: Ausgabe von `cat /root/gh-swiminstructor`, alles inklusive der BEGIN- und END-Zeile.
   - `DEPLOY_KNOWN_HOSTS`: Ausgabe von
     `echo "<host> $(cut -d' ' -f1,2 /etc/ssh/ssh_host_ed25519_key.pub)"` (bei anderem Port als 22 statt
     `<host>` die Form `[<host>]:<port>`).

   Danach den privaten Schlüssel vom Server löschen: `rm /root/gh-swiminstructor /root/gh-swiminstructor.pub`.
4. Einmal von Hand starten (*Actions → Backend Deploy → Run workflow*) und im Log auf
   "Deploy erfolgreich" achten.

## Logs

```bash
docker logs -f swiminstructor-backend             # live mitlesen
docker logs --since 1h swiminstructor-backend
```

Jeder Request und jeder Fehler steht als JSON-Zeile im Log (rotiert bei 10 MB, 5 Dateien).
Der Token wird nie geloggt. Health-Checks werden bewusst nicht protokolliert.

Docker löscht diese Logs, sobald der Container neu erstellt wird (bei jedem Deploy und bei
`--force-recreate`). `deploy.sh` sichert sie deshalb vorher nach `/var/log/swiminstructor/`
(eine `.log.gz` pro Deploy, 30 Tage aufbewahrt):

```bash
ls -lt /var/log/swiminstructor/
zcat /var/log/swiminstructor/backend-<Zeitstempel>.log.gz | grep '"level":50'   # nur Fehler
```

## Backups

Auf dem Server liegt wenig Zustand, Trainingsdaten speichert er nicht. Gesichert werden
zwei Dinge:

- `/etc/swiminstructor/backend.env` mit API-Token und Anthropic-Key. Geht sie verloren, musst du
  einen neuen Token erzeugen, ihn in der App eintragen und den Key neu anlegen.
- Das Volume `swim_data` mit dem letzten gültigen Plan. Er ist nur Cache und Fallback, ohne ihn
  läuft alles weiter, bis Claude wieder einen Plan liefert.

`backend/deploy/backup.sh` packt beides in ein Archiv unter `/var/backups/swiminstructor/`
(nur für root lesbar) und löscht Archive, die älter als 14 Tage sind. Einmal von Hand testen:

```bash
/opt/stack/swiminstructor/backend/deploy/backup.sh
# Backup erstellt: /var/backups/swiminstructor/swiminstructor-2026-10-03_031500.tar.gz (4.0K)
```

Dann täglich per Cron laufen lassen (`crontab -e` als root):

```cron
15 3 * * * /opt/stack/swiminstructor/backend/deploy/backup.sh >> /var/log/swiminstructor-backup.log 2>&1
```

Ein Backup nur auf demselben Server hilft nicht, wenn der Server selbst ausfällt. Nimm den Ordner
`/var/backups/swiminstructor/` deshalb in die Sicherung auf, die du für die anderen Dienste
ohnehin nach außen schickst. Weil das Archiv Token und API-Key enthält, gehört es nur an einen
verschlüsselten Ort. Hast du noch keine externe Sicherung, sichere zumindest die `backend.env`
zusätzlich in deinem Passwort-Manager (Vaultwarden).

Wiederherstellen:

```bash
mkdir /tmp/restore && tar -xzf /var/backups/swiminstructor/swiminstructor-<Zeitstempel>.tar.gz -C /tmp/restore
install -m 600 /tmp/restore/backend.env /etc/swiminstructor/backend.env
cd /opt/stack/swiminstructor/backend && docker compose up -d --force-recreate
tar -xf /tmp/restore/data.tar -C /tmp/restore
docker run --rm --volumes-from swiminstructor-backend -v /tmp/restore/data:/restore:ro \
  alpine cp -a /restore/. /data/
rm -rf /tmp/restore
```

## Nutzer (ein Token je Person)

Jede Person bekommt einen eigenen Token. Damit hat sie ihren eigenen gespeicherten Tagesplan und ihr eigenes
Aufrufbudget (`PLAN_MAX_GENERATIONS_PER_HOUR` und `_PER_DAY` gelten je Nutzer), und ein gesperrter Token betrifft
nur sie. Der Token aus `API_TOKEN` ist der Besitzer (`owner`) und Admin; seine Daten liegen wie bisher direkt in
`/data`, die der anderen unter `/data/users/<kennung>/`.

```bash
docker exec swiminstructor-backend node dist/cli/users.js add anna --name "Anna"   # zeigt den Token einmal
docker exec swiminstructor-backend node dist/cli/users.js list
docker exec swiminstructor-backend node dist/cli/users.js rotate anna             # neuer Token, alter gilt nicht mehr
docker exec swiminstructor-backend node dist/cli/users.js disable anna            # sperren (enable: entsperren)
docker exec swiminstructor-backend node dist/cli/users.js remove anna
```

Der Server liest `users.json` bei Änderungen selbst neu, ein Neustart ist nicht nötig. In der Datei steht nur der
SHA-256 jedes Tokens. Den Token trägt die Person in der App unter *Einstellungen → Server* ein. Über alle Nutzer
zusammen gilt zusätzlich eine Kostenbremse für den ganzen Server (`PLAN_MAX_GENERATIONS_TOTAL_PER_HOUR`, Standard
15, und `PLAN_MAX_GENERATIONS_TOTAL_PER_DAY`, Standard 60). Admin-Rechte für weitere Nutzer gibt `add … --admin`.

## Monitoring

### Nutzung und Kosten

Jede Plan-Anfrage landet mit Nutzer, Plan-Art, Ergebnis (`claude`, `cache`, `fallback`, `failed`), Ausfallgrund,
Modell, Token, Dauer und geschätzten Kosten in `/data/metrics/usage-<Tag>.jsonl` (120 Tage aufbewahrt). Die
Auswertung liefert der Server Admins:

```bash
curl -s -H "Authorization: Bearer <TOKEN>" "https://swiminstructor.kellner.v6.rocks/v1/admin/usage?days=7" | jq '.total, .days[-1]'
curl -s -H "Authorization: Bearer <TOKEN>" https://swiminstructor.kellner.v6.rocks/v1/admin/users | jq
```

Je Tag: Anfragen, Claude-Aufrufe, Ergebnisse, Fehlerquote (Fallback und Ausfall), Gründe, Token, Kosten, Dauer je
Plan-Art (Median und 95. Perzentil) und je Nutzer. Die Kosten sind eine Schätzung nach Listenpreis (Opus $4/$20,
Sonnet $2/$10, Haiku $1/$5 je Million Token; unbekannte Modelle wie Opus); maßgeblich bleibt die Anthropic Console.

### Alarme

Mit `ALERT_WEBHOOK_URL` in `/etc/swiminstructor/backend.env` meldet der Server sich selbst:

| Alarm | Wann | Wie oft |
|---|---|---|
| Tageskosten | Kosten heute über `ALERT_DAILY_COST_USD` (Standard 5) | einmal am Tag |
| Pläne fallen aus | in der letzten Stunde mindestens `ALERT_FAILURES_PER_HOUR` (3) Ausfälle von Claude oder der Sicherheitsschicht und mindestens `ALERT_FAILURE_RATE` (0,5) aller Anfragen | höchstens alle 3 Stunden |
| Konfigurationsfehler | Key ungültig (`auth`), Anfrage abgelehnt (`bad_request`), kein Key | höchstens alle 6 Stunden |
| Budget erschöpft | ein Nutzer hat sein Aufrufbudget erreicht | einmal je Nutzer und Tag |

Am einfachsten mit [ntfy](https://ntfy.sh) (App aufs iPhone, Thema mit schwer zu ratendem Namen abonnieren):

```bash
printf 'ALERT_WEBHOOK_URL=https://ntfy.sh/<geheimes-thema>\n' >> /etc/swiminstructor/backend.env
cd /opt/stack/swiminstructor/backend && docker compose up -d --force-recreate
```

Slack und Discord gehen auch (`ALERT_WEBHOOK_FORMAT=slack` bzw. `discord` mit der Webhook-URL), `json` schickt
`{"title", "message"}` an einen eigenen Empfänger.

### Server antwortet nicht

Fällt der Container ganz aus, kann er sich nicht selbst melden. Dafür prüft `deploy/healthcheck.sh` von außerhalb
des Containers und meldet über denselben Webhook, wenn `/health` zweimal hintereinander nicht antwortet, und noch
einmal, wenn er wieder da ist (`crontab -e` als root):

```cron
*/5 * * * * /opt/stack/swiminstructor/backend/deploy/healthcheck.sh >/dev/null 2>&1
```

### Weitere Dienste

Der Container startet nach einem Absturz von selbst neu (`restart: unless-stopped`), und Docker
markiert ihn als `unhealthy`, wenn `/health` nicht mehr antwortet. Benachrichtigt wirst du davon
aber nicht. Dafür zwei kostenlose Dienste, beide ohne Änderung am Server:

1. **Erreichbarkeit von außen**: Ein Uptime-Monitor (z. B. UptimeRobot, oder Uptime Kuma, falls
   du es schon betreibst) ruft alle 5 Minuten `https://swiminstructor.kellner.v6.rocks/health`
   auf, erwartet Status 200 und das Stichwort `"ok"`, und meldet sich per Mail oder Push. Schalte
   dort auch die Warnung vor Ablauf des Zertifikats ein. Das deckt Container, Caddy, DNS und
   Zertifikat in einem ab.
2. **Backup bleibt aus**: Lege bei healthchecks.io einen Check mit Periode 1 Tag an und trage die
   Ping-URL im Cron-Eintrag ein. Das Skript meldet Erfolg und Fehler, und der Dienst schlägt Alarm,
   wenn ein Tag lang nichts kommt:

```cron
15 3 * * * HEALTHCHECK_URL=https://hc-ping.com/<uuid> /opt/stack/swiminstructor/backend/deploy/backup.sh >> /var/log/swiminstructor-backup.log 2>&1
```

Die Kosten der Claude-Aufrufe siehst du in `/v1/admin/usage` und in den Alarmen; die harte Grenze bleibt das
Ausgabenlimit in der Anthropic Console (siehe oben).

## Token wechseln

Für einen weiteren Nutzer: `users.js rotate <kennung>` (siehe oben). Für den Besitzer, falls der Token je in falsche
Hände gerät:

```bash
nano /etc/swiminstructor/backend.env              # neuen Wert: openssl rand -hex 32
cd /opt/stack/swiminstructor/backend && docker compose up -d --force-recreate
```

Danach den neuen Token in der App eintragen.
