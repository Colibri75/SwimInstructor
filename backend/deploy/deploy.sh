#!/usr/bin/env bash
# Aktualisiert das Backend auf dem Server: neuester Stand aus main, bauen, Dienst neu starten.
# Aufruf auf dem Server:  /opt/swiminstructor/backend/deploy/deploy.sh
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/swiminstructor}"
SERVICE="swiminstructor-backend"
PORT="${PORT:-3000}"

cd "$APP_DIR"
git pull --ff-only origin main

cd backend
npm ci
npm run build
npm prune --omit=dev

sudo systemctl restart "$SERVICE"
sleep 2
systemctl is-active --quiet "$SERVICE" || { journalctl -u "$SERVICE" -n 30 --no-pager; exit 1; }
curl -fsS "http://127.0.0.1:${PORT}/health" && echo
echo "Deploy erfolgreich."
