#!/usr/bin/env bash
# Fuehrt die Szenario-Bewertung (npm run eval:scenarios) in einem Wegwerf-Container aus, fuer Server
# ohne Node (z. B. den Produktionsserver). Der API-Key kommt aus der Env-Datei und wird nie angezeigt.
#
# Aufruf:  backend/scripts/eval-in-docker.sh [Ausgabedatei]
# Standard-Ausgabe: docs/eval-runs/plan-eval-<Datum-Uhrzeit>.md im Repo. docs/plan-eval.md ist das gepflegte
# Bewertungsdokument und wird nie vom Skript ueberschrieben.
set -euo pipefail

BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-/etc/swiminstructor/backend.env}"
OUT="${1:-$BACKEND_DIR/../docs/eval-runs/plan-eval-$(date +%Y-%m-%d-%H%M).md}"
mkdir -p "$(dirname "$OUT")"

if ! grep -q '^ANTHROPIC_API_KEY=.' "$ENV_FILE" 2>/dev/null; then
  echo "In $ENV_FILE fehlt ANTHROPIC_API_KEY. Siehe docs/backend-deploy.md, Abschnitt 'Claude-API-Key einrichten'." >&2
  exit 1
fi

echo "Das sendet je Szenario einen Tagesplan, einen Plan der naechsten 7 Tage und einen Gesamtplan an die Claude-API (9 Szenarien, 27 Anfragen) und kostet echtes Geld (geschaetzt rund 1,50 US-Dollar)." >&2
read -r -p "Weiter mit Enter, Abbruch mit Strg+C. " _ >&2

# Der Quellordner wird nur lesend eingehaengt und im Container kopiert, damit im Repo nichts
# (node_modules) zurueckbleibt. Die Installationsausgabe geht auf stderr, damit auf stdout nur das
# Markdown landet.
docker run --rm --env-file "$ENV_FILE" -v "$BACKEND_DIR":/src:ro node:22-alpine \
  sh -c 'cp -r /src /app && cd /app && npm ci --silent >&2 && npx tsx scripts/eval-scenarios.ts' \
  > "$OUT"

echo "Fertig: $OUT" >&2
