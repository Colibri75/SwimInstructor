#!/usr/bin/env bash
# Aktualisiert das Backend auf dem Server: neuester Stand aus main, Image neu bauen, Container neu starten.
# Aufruf auf dem Server:  <Repo-Ordner>/backend/deploy/deploy.sh   (z. B. /opt/stack/swiminstructor)
set -euo pipefail

# Repo-Ordner aus dem Ort des Skripts ableiten (backend/deploy/ -> zwei Ebenen hoch), damit es
# egal ist, wohin das Repo geklont wurde.
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST_PORT="${HOST_PORT:-3100}"
# Docker loescht die Logs eines Containers, sobald er neu erstellt wird. Deshalb vor jedem Deploy
# sichern, sonst sind Fehler aus der Zeit vor dem Update weg.
LOG_ARCHIVE_DIR="${LOG_ARCHIVE_DIR:-/var/log/swiminstructor}"
LOG_KEEP_DAYS="${LOG_KEEP_DAYS:-30}"

cd "$APP_DIR"
git pull --ff-only origin main

if docker inspect swiminstructor-backend >/dev/null 2>&1; then
  mkdir -p "$LOG_ARCHIVE_DIR"
  chmod 700 "$LOG_ARCHIVE_DIR"
  docker logs swiminstructor-backend 2>&1 | gzip > "$LOG_ARCHIVE_DIR/backend-$(date +%Y-%m-%d_%H%M%S).log.gz"
  find "$LOG_ARCHIVE_DIR" -name 'backend-*.log.gz' -type f -mtime +"$LOG_KEEP_DAYS" -delete
fi

cd backend
docker compose up -d --build

# Auf den Healthcheck des Containers warten (max. ca. 30 s)
for _ in $(seq 1 15); do
  status=$(docker inspect --format '{{.State.Health.Status}}' swiminstructor-backend 2>/dev/null || echo "unknown")
  [ "$status" = "healthy" ] && break
  sleep 2
done
if [ "$status" != "healthy" ]; then
  echo "Container ist nicht gesund (Status: $status). Letzte Logzeilen:" >&2
  docker logs --tail 30 swiminstructor-backend >&2
  exit 1
fi

curl -fsS "http://127.0.0.1:${HOST_PORT}/health" && echo
docker image prune -f >/dev/null
echo "Deploy erfolgreich."
