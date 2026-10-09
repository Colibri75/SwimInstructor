#!/usr/bin/env bash
# Prüft von außen, ob das Backend lebt, und meldet einen Ausfall (und die Erholung) per Alarm-Webhook. Der Server
# selbst kann nicht melden, dass er nicht läuft; dafür ist dieses Skript da.
#
# Aufruf als root auf dem Server, z. B. alle 5 Minuten per Cron (siehe docs/backend-deploy.md):
#   */5 * * * * <Repo-Ordner>/backend/deploy/healthcheck.sh
#
# Liest ALERT_WEBHOOK_URL und ALERT_WEBHOOK_FORMAT (ntfy, slack, discord, json) aus der Konfiguration des Backends.
# Gemeldet wird nur beim Wechsel (gesund -> krank -> gesund), nicht bei jedem Lauf.
set -euo pipefail

ENV_FILE="${ENV_FILE:-/etc/swiminstructor/backend.env}"
HEALTH_URL="${HEALTH_URL:-http://127.0.0.1:3100/health}"
STATE_FILE="${STATE_FILE:-/var/lib/swiminstructor/health.state}"
# So viele Fehlversuche hintereinander, bevor gemeldet wird (ein Neustart beim Deploy dauert etwa 10 s).
FAILS_BEFORE_ALERT="${FAILS_BEFORE_ALERT:-2}"

read_env() {
  [ -r "$ENV_FILE" ] || return 0
  grep -E "^$1=" "$ENV_FILE" | tail -n1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'
}

WEBHOOK_URL="${ALERT_WEBHOOK_URL:-$(read_env ALERT_WEBHOOK_URL)}"
FORMAT="${ALERT_WEBHOOK_FORMAT:-$(read_env ALERT_WEBHOOK_FORMAT)}"
if [ -z "$FORMAT" ]; then
  case "$WEBHOOK_URL" in *ntfy*) FORMAT=ntfy ;; *) FORMAT=json ;; esac
fi

notify() {
  local title="$1" message="$2"
  [ -n "$WEBHOOK_URL" ] || { echo "$title: $message"; return 0; }
  case "$FORMAT" in
    ntfy) curl -fsS -m 10 -o /dev/null -H "Title: $title" -H "Tags: warning" -d "$message" "$WEBHOOK_URL" ;;
    slack) curl -fsS -m 10 -o /dev/null -H 'Content-Type: application/json' -d "$(jq -n --arg t "*$title*"$'\n'"$message" '{text: $t}')" "$WEBHOOK_URL" ;;
    discord) curl -fsS -m 10 -o /dev/null -H 'Content-Type: application/json' -d "$(jq -n --arg t "**$title**"$'\n'"$message" '{content: $t}')" "$WEBHOOK_URL" ;;
    *) curl -fsS -m 10 -o /dev/null -H 'Content-Type: application/json' -d "$(jq -n --arg t "$title" --arg m "$message" '{title: $t, message: $m}')" "$WEBHOOK_URL" ;;
  esac
}

mkdir -p "$(dirname "$STATE_FILE")"
previous_fails=0
[ -r "$STATE_FILE" ] && previous_fails="$(cat "$STATE_FILE")"

if curl -fsS -m 10 -o /dev/null "$HEALTH_URL"; then
  if [ "$previous_fails" -ge "$FAILS_BEFORE_ALERT" ]; then
    notify "PeakSmith: Server wieder erreichbar" "Das Backend antwortet wieder ($HEALTH_URL)."
  fi
  echo 0 > "$STATE_FILE"
  exit 0
fi

fails=$((previous_fails + 1))
echo "$fails" > "$STATE_FILE"
if [ "$fails" -eq "$FAILS_BEFORE_ALERT" ]; then
  status=$(docker inspect --format '{{.State.Status}}/{{if .State.Health}}{{.State.Health.Status}}{{end}}' swiminstructor-backend 2>/dev/null || echo "kein Container")
  notify "PeakSmith: Server antwortet nicht" "Health-Check $HEALTH_URL schlägt seit $fails Läufen fehl (Container: $status)."
fi
exit 1
