#!/usr/bin/env bash
# Fuehrt die Bewertung der Plaene (Gesamtplan, sieben Tage, Tag, Ueberarbeitung) in einem Wegwerf-Container aus, fuer
# Server ohne Node (z. B. den Produktionsserver). Der API-Key kommt aus der Env-Datei und wird nie angezeigt.
#
# Aufruf:
#   backend/scripts/eval-in-docker.sh [Ausgabedatei]
# Standard-Ausgabe: docs/eval-runs/multisport-eval-<Datum-Uhrzeit>.md im Repo.
#
# Der Lauf schreibt Claudes Antworten als neue Aufzeichnungen nach backend/scenarios/multisport/recorded/ (ersetzt
# die bisherigen); danach committen, dann spielt die CI sie ab.
# Nur einige Szenarien: EVAL_ONLY=01,06 backend/scripts/eval-in-docker.sh
set -euo pipefail

BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-/etc/swiminstructor/backend.env}"
STAMP="$(date +%Y-%m-%d-%H%M)"
OUT="${1:-$BACKEND_DIR/../docs/eval-runs/multisport-eval-$STAMP.md}"
mkdir -p "$(dirname "$OUT")"

if ! grep -q '^ANTHROPIC_API_KEY=.' "$ENV_FILE" 2>/dev/null; then
  echo "In $ENV_FILE fehlt ANTHROPIC_API_KEY. Siehe docs/backend-deploy.md, Abschnitt 'Claude-API-Key einrichten'." >&2
  exit 1
fi

echo "Das sendet je Szenario einen Gesamtplan, einen Plan der naechsten 7 Tage, einen Tagesplan und bei Feedback eine Ueberarbeitung an die Claude-API (9 Szenarien, 29 Anfragen) und kostet echtes Geld (geschaetzt rund 4 US-Dollar)." >&2
read -r -p "Weiter mit Enter, Abbruch mit Strg+C. " _ >&2

# --init: Strg+C beendet den Container wirklich (sonst laeuft er im Hintergrund weiter und fragt Claude weiter).
# Der Quellordner wird nur lesend eingehaengt und im Container kopiert, damit im Repo nichts
# (node_modules) zurueckbleibt. Die Installationsausgabe geht auf stderr, damit auf stdout nur das
# Markdown landet. Nur der Ordner der Aufzeichnungen ist beschreibbar; die Dateien gehoeren danach dir.
RECORDED="$BACKEND_DIR/scenarios/multisport/recorded"
docker run --rm --init --env-file "$ENV_FILE" -e EVAL_RECORD=1 -e EVAL_RECORD_DIR=/recorded -e EVAL_ONLY \
  -e HOST_IDS="$(id -u):$(id -g)" -v "$BACKEND_DIR":/src:ro -v "$RECORDED":/recorded node:22-alpine \
  sh -c 'cp -r /src /app && cd /app && npm ci --silent >&2 && npx tsx scripts/eval-multisport.ts; status=$?; chown -R "$HOST_IDS" /recorded; exit $status' \
  > "$OUT"
echo "Fertig: $OUT. Neue Aufzeichnungen in $RECORDED, bitte committen." >&2
