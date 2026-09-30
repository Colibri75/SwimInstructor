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

Im Browser muss beim Aufruf von `https://swiminstructor.kellner.v6.rocks/health` ein gültiges
Schloss erscheinen (keine Zertifikatswarnung). Prüfe außerdem, dass deine anderen Dienste (Financial,
Vaultwarden, Immich, Nextcloud) weiter normal erreichbar sind.

Und von außen darf der Container-Port nicht direkt offen sein:

```bash
curl -m 5 http://144.91.69.144:3100/health      # muss fehlschlagen (Timeout/Connection refused)
```

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

## Token wechseln

Falls der Token je in falsche Hände gerät:

```bash
nano /etc/swiminstructor/backend.env              # neuen Wert: openssl rand -hex 32
cd /opt/stack/swiminstructor/backend && docker compose up -d --force-recreate
```

Danach den neuen Token in der App eintragen.
