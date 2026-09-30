#!/usr/bin/env bash
# Aktualisiert das Backend auf dem Server: neuester Stand aus main, Image neu bauen, Container neu starten.
# Aufruf auf dem Server:  /opt/swiminstructor/backend/deploy/deploy.sh
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/swiminstructor}"
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
