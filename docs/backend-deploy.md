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

## 5. Prüfen (das ist die Definition of Done von M4)

Von deinem Rechner aus, nicht vom Server:

```bash
curl -i https://swiminstructor.kellner.v6.rocks/health
# HTTP/2 200 ... {"status":"ok",...}

curl -i https://swiminstructor.kellner.v6.rocks/v1/status
# HTTP/2 401 ... {"error":"unauthorized"}

curl -i -H "Authorization: Bearer <DEIN-TOKEN>" https://swiminstructor.kellner.v6.rocks/v1/status
# HTTP/2 200 ... {"status":"authenticated"}
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
wartet auf den Healthcheck.

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

## Monitoring

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

Die Kosten der Claude-Aufrufe überwachst du über das Ausgabenlimit in der Anthropic Console (siehe
oben).

## Token wechseln

Falls der Token je in falsche Hände gerät:

```bash
nano /etc/swiminstructor/backend.env              # neuen Wert: openssl rand -hex 32
cd /opt/stack/swiminstructor/backend && docker compose up -d --force-recreate
```

Danach den neuen Token in der App eintragen.
