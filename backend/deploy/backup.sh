#!/usr/bin/env bash
# Sichert alles, was das Backend auf dem Server an Zustand hat:
#   - /etc/swiminstructor/backend.env  (API-Token, Anthropic-Key; ohne sie startet nichts)
#   - /data aus dem Container          (letzter gueltiger Plan, Fallback bei Claude-Ausfall)
# Ergebnis: ein Archiv pro Lauf in BACKUP_DIR (nur fuer root lesbar), aeltere als KEEP_DAYS Tage
# werden geloescht.
#
# Aufruf als root auf dem Server, z. B. taeglich per Cron (siehe docs/backend-deploy.md):
#   <Repo-Ordner>/backend/deploy/backup.sh
#
# Optional: HEALTHCHECK_URL (z. B. https://hc-ping.com/<uuid>) wird nach Erfolg aufgerufen und bei
# einem Fehler mit /fail. So meldet sich ein Dienst wie healthchecks.io, wenn das Backup ausbleibt.
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/swiminstructor}"
KEEP_DAYS="${KEEP_DAYS:-14}"
ENV_FILE="${ENV_FILE:-/etc/swiminstructor/backend.env}"
CONTAINER="${CONTAINER:-swiminstructor-backend}"
HEALTHCHECK_URL="${HEALTHCHECK_URL:-}"

ping_healthcheck() {
  [ -n "$HEALTHCHECK_URL" ] || return 0
  curl -fsS -m 10 --retry 3 -o /dev/null "${HEALTHCHECK_URL}$1" || true
}
trap 'ping_healthcheck /fail' ERR

umask 077
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

stamp="$(date +%Y-%m-%d_%H%M%S)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cp "$ENV_FILE" "$work/backend.env"
# docker cp liefert /data als tar-Strom und funktioniert auch beim schreibgeschuetzten Container.
docker cp "$CONTAINER:/data" - > "$work/data.tar"

archive="$BACKUP_DIR/swiminstructor-$stamp.tar.gz"
tar -czf "$archive.tmp" -C "$work" backend.env data.tar
mv "$archive.tmp" "$archive"

# Archiv kurz pruefen, bevor alte geloescht werden.
tar -tzf "$archive" | grep -qx 'backend.env'

find "$BACKUP_DIR" -name 'swiminstructor-*.tar.gz' -type f -mtime +"$KEEP_DAYS" -delete

ping_healthcheck ""
echo "Backup erstellt: $archive ($(du -h "$archive" | cut -f1))"
