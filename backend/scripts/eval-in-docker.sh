#!/usr/bin/env bash
# Fuehrt die Szenario-Bewertung in einem Wegwerf-Container aus, fuer Server ohne Node (z. B. den Produktionsserver).
# Der API-Key kommt aus der Env-Datei und wird nie angezeigt.
#
# Aufruf:
#   backend/scripts/eval-in-docker.sh [Ausgabedatei]              Schwimmplan v1 (npm run eval:scenarios)
#   backend/scripts/eval-in-docker.sh multisport [Ausgabedatei]   Plan v2 fuer mehrere Sportarten (npm run eval:multisport)
# Standard-Ausgabe: docs/eval-runs/plan-eval-<Datum-Uhrzeit>.md bzw. multisport-eval-<Datum-Uhrzeit>.md im Repo.
# docs/plan-eval.md ist das gepflegte Bewertungsdokument und wird nie vom Skript ueberschrieben.
#
# Bei multisport schreibt der Lauf Claudes Antworten als neue Aufzeichnungen nach
# backend/scenarios/multisport/recorded/ (ersetzt die synthetischen); danach committen, dann spielt die CI sie ab.
# Nur einige Szenarien: EVAL_ONLY=01,06 backend/scripts/eval-in-docker.sh multisport
set -euo pipefail

BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-/etc/swiminstructor/backend.env}"
MODE="v1"
if [ "${1:-}" = "multisport" ]; then
  MODE="multisport"
  shift
fi
STAMP="$(date +%Y-%m-%d-%H%M)"
if [ "$MODE" = "multisport" ]; then
  OUT="${1:-$BACKEND_DIR/../docs/eval-runs/multisport-eval-$STAMP.md}"
else
  OUT="${1:-$BACKEND_DIR/../docs/eval-runs/plan-eval-$STAMP.md}"
fi
mkdir -p "$(dirname "$OUT")"

if ! grep -q '^ANTHROPIC_API_KEY=.' "$ENV_FILE" 2>/dev/null; then
  echo "In $ENV_FILE fehlt ANTHROPIC_API_KEY. Siehe docs/backend-deploy.md, Abschnitt 'Claude-API-Key einrichten'." >&2
  exit 1
fi

if [ "$MODE" = "multisport" ]; then
  echo "Das sendet je Szenario einen Gesamtplan, einen Plan der naechsten 7 Tage, einen Tagesplan und bei Feedback eine Ueberarbeitung an die Claude-API (9 Szenarien, 29 Anfragen) und kostet echtes Geld (geschaetzt rund 4 US-Dollar)." >&2
else
  echo "Das sendet je Szenario einen Tagesplan, einen Plan der naechsten 7 Tage und einen Gesamtplan an die Claude-API (9 Szenarien, 27 Anfragen) und kostet echtes Geld (geschaetzt rund 1,50 US-Dollar)." >&2
fi
read -r -p "Weiter mit Enter, Abbruch mit Strg+C. " _ >&2

# --init: Strg+C beendet den Container wirklich (sonst laeuft er im Hintergrund weiter und fragt Claude weiter).
# Der Quellordner wird nur lesend eingehaengt und im Container kopiert, damit im Repo nichts
# (node_modules) zurueckbleibt. Die Installationsausgabe geht auf stderr, damit auf stdout nur das
# Markdown landet. Nur der Ordner der Aufzeichnungen ist beschreibbar; die Dateien gehoeren danach dir.
if [ "$MODE" = "multisport" ]; then
  RECORDED="$BACKEND_DIR/scenarios/multisport/recorded"
  docker run --rm --init --env-file "$ENV_FILE" -e EVAL_RECORD=1 -e EVAL_RECORD_DIR=/recorded -e EVAL_ONLY \
    -e HOST_IDS="$(id -u):$(id -g)" -v "$BACKEND_DIR":/src:ro -v "$RECORDED":/recorded node:22-alpine \
    sh -c 'cp -r /src /app && cd /app && npm ci --silent >&2 && npx tsx scripts/eval-multisport.ts; status=$?; chown -R "$HOST_IDS" /recorded; exit $status' \
    > "$OUT"
  echo "Fertig: $OUT. Neue Aufzeichnungen in $RECORDED, bitte committen." >&2
else
  docker run --rm --init --env-file "$ENV_FILE" -v "$BACKEND_DIR":/src:ro node:22-alpine \
    sh -c 'cp -r /src /app && cd /app && npm ci --silent >&2 && npx tsx scripts/eval-scenarios.ts' \
    > "$OUT"
  echo "Fertig: $OUT" >&2
fi
