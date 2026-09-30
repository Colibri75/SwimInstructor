# Backend auf dem Server einrichten (Docker + Caddy)

Das Backend läuft als Docker-Container und veröffentlicht seinen Port nur auf `127.0.0.1:3100`
des Servers. Dein bestehender **Caddy** nimmt die Anfragen von außen an, kümmert sich um HTTPS
und leitet sie an den Container weiter. Die Financial-App bleibt unangetastet: Du ergänzt nur
einen Abschnitt in der Caddyfile.

Die Befehle gehen davon aus, dass du als `root` arbeitest (sonst `sudo` davorsetzen) und dass
Caddy direkt auf dem Server läuft (`systemctl is-active caddy` meldet `active`). Läuft Caddy
selbst in einem Docker-Container, gilt Schritt 5 anders, sag dann Bescheid.

## Voraussetzungen

- Docker mit Compose-Plugin (`docker compose version` liefert eine Version)
- Ein Hostname, der auf den Server zeigt (dein DynDNS-Name oder ein zweiter dafür)
- Port 80 und 443 sind von außen erreichbar (für die Financial-App vermutlich schon)
- Ein GitHub-Token (PAT) mit Lesezugriff auf das Repo, weil das Repo privat ist
- Der Host-Port 3100 ist frei: `ss -tlnp | grep ':3100 '` liefert nichts

## 1. Code auf den Server holen

```bash
mkdir -p /opt/swiminstructor
git clone https://github.com/Colibri75/SwimInstructor.git /opt/swiminstructor
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
cd /opt/swiminstructor/backend
docker compose up -d --build
docker compose ps                 # Status sollte "healthy" werden (nach ca. 5-10 s)
curl -s http://127.0.0.1:3100/health
# {"status":"ok","uptimeSeconds":3}
```

Der erste Build dauert ein bis zwei Minuten. Läuft der Container nicht:
`docker logs swiminstructor-backend`.

## 4. DNS: Hostname für die API

Damit Caddy ein Zertifikat holen kann, muss der Hostname auf den Server zeigen.

- **Variante A (empfohlen):** Lege bei deinem DynDNS-Anbieter einen zweiten Hostnamen an, der auf
  denselben Server zeigt (z. B. `swim-api.<deine-dyndns-domain>`). Nicht jeder Anbieter erlaubt
  das, dann Variante B.
- **Variante B:** Kein zweiter Hostname. Die API hängt dann als Pfad `/swim/` an deinem
  bestehenden Hostnamen.

## 5. Caddy einrichten

Öffne die Caddyfile (meist `/etc/caddy/Caddyfile`) und ergänze den Abschnitt aus
`backend/deploy/Caddyfile.example` für deine Variante. Variante A ist ein eigener Block, bei
Variante B kommt `handle_path /swim/* { ... }` in den bestehenden Block deines Hostnamens.

Erst prüfen, dann laden. Das Laden ist ohne Ausfall, die Financial-App merkt nichts:

```bash
caddy validate --config /etc/caddy/Caddyfile     # muss "Valid configuration" melden
systemctl reload caddy
journalctl -u caddy -n 20 --no-pager             # bei Variante A: Zertifikat wird geholt
```

Bei einem Fehler in der Prüfung lädst du nicht neu, dann läuft alles unverändert weiter.

## 6. Prüfen (das ist die Definition of Done von M4)

Von deinem Rechner aus, nicht vom Server. Bei Variante B lautet der Pfad `/swim/health`
statt `/health`:

```bash
curl -i https://<dein-api-hostname>/health
# HTTP/2 200 ... {"status":"ok",...}

curl -i https://<dein-api-hostname>/v1/status
# HTTP/2 401 ... {"error":"unauthorized"}

curl -i -H "Authorization: Bearer <DEIN-TOKEN>" https://<dein-api-hostname>/v1/status
# HTTP/2 200 ... {"status":"authenticated"}
```

Im Browser muss beim Aufruf von `https://<dein-api-hostname>/health` ein gültiges Schloss
erscheinen (keine Zertifikatswarnung). Prüfe außerdem, dass die Financial-App weiter normal
erreichbar ist.

Und von außen darf der Container-Port nicht direkt offen sein:

```bash
curl -m 5 http://144.91.69.144:3100/health      # muss fehlschlagen (Timeout/Connection refused)
```

## Aktualisieren

Nach jedem Merge, der das Backend ändert:

```bash
/opt/swiminstructor/backend/deploy/deploy.sh
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
cd /opt/swiminstructor/backend && docker compose up -d --force-recreate
```

Danach den neuen Token in der App eintragen.
