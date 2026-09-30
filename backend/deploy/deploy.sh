#!/usr/bin/env bash
# Aktualisiert das Backend auf dem Server: neuester Stand aus main, Image neu bauen, Container neu starten.
# Aufruf auf dem Server:  <Repo-Ordner>/backend/deploy/deploy.sh   (z. B. /opt/stack/swiminstructor)
set -euo pipefail

# Repo-Ordner aus dem Ort des Skripts ableiten (backend/deploy/ -> zwei Ebenen hoch), damit es
# egal ist, wohin das Repo geklont wurde.
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST_PORT="${HOST_PORT:-3100}"

cd "$APP_DIR"
git pull --ff-only origin main

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
