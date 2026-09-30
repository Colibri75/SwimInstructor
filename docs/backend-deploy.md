# Backend auf dem Ubuntu-Server einrichten

Das Backend ist ein kleiner Node-Dienst, der nur auf `127.0.0.1:3000` lauscht. Von außen ist er
über deinen bestehenden **nginx** erreichbar, der HTTPS übernimmt. Die Financial-App bleibt
unangetastet: Du legst nur eine neue nginx-Konfigurationsdatei an.

Die Anleitung geht von nginx und einem Nutzer mit `sudo` aus. Läuft bei dir Apache oder Caddy,
sag Bescheid, dann passe ich Schritt 6 an.

## Voraussetzungen

- Ubuntu-Server mit SSH-Zugang und `sudo`
- Ein Hostname, der auf den Server zeigt (dein DynDNS-Name oder ein zweiter dafür)
- Port 80 und 443 sind von außen erreichbar (für die Financial-App vermutlich schon)
- Ein GitHub-Token (PAT) mit Lesezugriff auf das Repo, weil das Repo privat ist

## 1. Node.js 22 installieren

```bash
node -v   # falls schon >= 20 vorhanden, weiter mit Schritt 2
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs git
node -v   # v22.x
```

## 2. Dienst-Nutzer und Code anlegen

```bash
# Eigener Nutzer ohne Login-Shell: der Dienst läuft nie als root
sudo useradd --system --no-create-home --shell /usr/sbin/nologin swiminstructor

sudo mkdir -p /opt/swiminstructor && sudo chown "$USER":"$USER" /opt/swiminstructor
git clone https://github.com/Colibri75/SwimInstructor.git /opt/swiminstructor
# Benutzername: Colibri75, Passwort: dein PAT (kein GitHub-Passwort)

cd /opt/swiminstructor/backend
npm ci
npm run build
npm prune --omit=dev
```

## 3. Geheimen Token und Konfiguration anlegen

```bash
sudo mkdir -p /etc/swiminstructor
TOKEN=$(openssl rand -hex 32)
sudo tee /etc/swiminstructor/backend.env >/dev/null <<EOF
API_TOKEN=$TOKEN
NODE_ENV=production
HOST=127.0.0.1
PORT=3000
EOF
sudo chmod 600 /etc/swiminstructor/backend.env
echo "Dein API-Token (jetzt sicher notieren, er wird für die App gebraucht):"
echo "$TOKEN"
```

Der Token steht danach nur in dieser Datei (lesbar nur für root). Er gehört später in die App
und nie in das Repo.

## 4. Dienst starten

```bash
sudo cp /opt/swiminstructor/backend/deploy/swiminstructor-backend.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now swiminstructor-backend
systemctl status swiminstructor-backend --no-pager

curl -s http://127.0.0.1:3000/health
# {"status":"ok","uptimeSeconds":3}
```

Läuft der Dienst nicht: `journalctl -u swiminstructor-backend -n 50 --no-pager`.

## 5. Firewall prüfen

Port 3000 darf **nicht** von außen offen sein (der Dienst lauscht ohnehin nur lokal):

```bash
sudo ufw status   # 80 und 443 erlaubt, 3000 nicht aufgeführt
```

## 6. nginx einrichten

Kopiere die Vorlage, trag deinen Hostnamen ein und prüfe die Konfiguration, bevor du nginx
neu lädst:

```bash
sudo cp /opt/swiminstructor/backend/deploy/nginx-swiminstructor.conf.example \
        /etc/nginx/sites-available/swiminstructor
sudo nano /etc/nginx/sites-available/swiminstructor     # server_name anpassen
sudo ln -s /etc/nginx/sites-available/swiminstructor /etc/nginx/sites-enabled/
sudo nginx -t                                            # muss "syntax is ok" melden
sudo systemctl reload nginx
```

Die Vorlage enthält zwei Varianten (steht im Kopf der Datei):

- **A (empfohlen):** eigener Hostname nur für die API. Sauber getrennt von der Financial-App.
- **B:** kein zweiter Hostname möglich. Dann hängst du einen `location /swim/`-Block an deinen
  bestehenden HTTPS-Server-Block. Die API liegt dann unter `https://<dein-hostname>/swim/`.

## 7. HTTPS-Zertifikat (Variante A)

```bash
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d <dein-api-hostname>
```

certbot ergänzt den 443-Block und die Weiterleitung von HTTP auf HTTPS selbst und erneuert das
Zertifikat automatisch. Bei Variante B ist das Zertifikat deines bestehenden Hostnamens schon da.

## 8. Prüfen (das ist die Definition of Done von M4)

Von deinem Rechner aus, nicht vom Server:

```bash
curl -i https://<dein-api-hostname>/health
# HTTP/2 200 ... {"status":"ok",...}

curl -i https://<dein-api-hostname>/v1/status
# HTTP/2 401 ... {"error":"unauthorized"}

curl -i -H "Authorization: Bearer <DEIN-TOKEN>" https://<dein-api-hostname>/v1/status
# HTTP/2 200 ... {"status":"authenticated"}
```

Auch im Browser muss beim Aufruf von `https://<dein-api-hostname>/health` ein gültiges Schloss
erscheinen (keine Zertifikatswarnung). Bei Variante B lautet der Pfad `/swim/health`.

## Aktualisieren

Nach jedem Merge, der das Backend ändert:

```bash
/opt/swiminstructor/backend/deploy/deploy.sh
```

Das Skript holt den neuesten Stand aus `main`, baut, startet den Dienst neu und prüft `/health`.

## Logs

```bash
journalctl -u swiminstructor-backend -f          # live mitlesen
journalctl -u swiminstructor-backend --since today
```

Jeder Request und jeder Fehler steht als JSON-Zeile im Journal. Der Token wird nie geloggt.
Health-Checks werden bewusst nicht protokolliert.

## Token wechseln

Falls der Token je in falsche Hände gerät:

```bash
sudo nano /etc/swiminstructor/backend.env    # neuen Wert: openssl rand -hex 32
sudo systemctl restart swiminstructor-backend
```

Danach den neuen Token in der App eintragen.
