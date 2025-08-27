#!/usr/bin/env bash
set -euo pipefail

# =========[ Configuration ]=========
MODEM_IP="192.168.1.1"      # IP address of the modem/router (powered directly from mains, not UPS)
CHECK_INTERVAL=60           # Seconds between checks (should match the systemd timer or cron interval)
OUTAGE_MINUTES=20           # Number of minutes of continuous outage before shutdown
EXTRA_PROBE="1.1.1.1"       # Optional external IP to reduce false positives (set empty "" to disable)

STATE_DIR="/var/lib/power-watch"   # Directory for storing state (counter)
STATE_FILE="$STATE_DIR/state"      # File that holds the counter value
LOG_TAG="power-watch"              # Identifier for syslog messages

# =========[ Helper Functions ]=========

# Log messages to syslog and stdout
log() { logger -t "$LOG_TAG" -- "$*"; echo "[$LOG_TAG] $*"; }

# Check if power is OK by testing modem reachability
is_power_ok() {
  # If the modem responds to ping, mains power is probably ON
  if ping -c1 -W2 "$MODEM_IP" >/dev/null 2>&1; then
    return 0
  fi

  # Optional: if the modem is down but external probe is reachable,
  # this could indicate a local network glitch rather than a power cut.
  if [[ -n "$EXTRA_PROBE" ]]; then
    if ping -c1 -W2 "$EXTRA_PROBE" >/dev/null 2>&1; then
      return 0
    fi
  fi

  # If modem is unreachable and optional probe is also down → assume mains outage
  return 1
}

# Check if a user is currently active
# Uses systemd-logind to detect non-idle, active sessions
is_user_active() {
  # Iterate over all sessions
  while read -r sid user seat rest; do
    [[ -z "$sid" ]] && continue
    # Only consider local sessions (tty, x11, wayland)
    local t
    t=$(loginctl show-session "$sid" -p Type --value 2>/dev/null || true)
    case "$t" in
      tty|x11|wayland)
        local active idle
        active=$(loginctl show-session "$sid" -p Active --value 2>/dev/null || echo no)
        idle=$(loginctl show-session "$sid" -p IdleHint --value 2>/dev/null || echo yes)
        if [[ "$active" == "yes" && "$idle" == "no" ]]; then
          return 0
        fi
      ;;
    esac
  done < <(loginctl list-sessions --no-legend 2>/dev/null || true)

  return 1
}

# =========[ Main Logic ]=========
main() {
  mkdir -p "$STATE_DIR"
  chmod 700 "$STATE_DIR"
  local needed_fail=$(( OUTAGE_MINUTES * 60 / CHECK_INTERVAL ))

  # Read previous counter
  local count=0
  if [[ -f "$STATE_FILE" ]]; then
    count=$(<"$STATE_FILE")
    [[ -z "$count" ]] && count=0
  fi

  if is_power_ok; then
    # Power is OK → reset counter
    if (( count > 0 )); then
      log "Power restored; reset counter (was $count)."
    fi
    echo 0 > "$STATE_FILE"
    exit 0
  else
    # Modem down → increment counter
    count=$((count + 1))
    echo "$count" > "$STATE_FILE"
    log "Possible mains outage: counter=$count/$needed_fail"
  fi

  # If threshold reached, check user activity before shutdown
  if (( count >= needed_fail )); then
    if is_user_active; then
      log "User is active; skipping shutdown despite outage threshold."
      # Keep counter at threshold so next check triggers again if still outage
      echo "$needed_fail" > "$STATE_FILE"
      exit 0
    fi

    log "Outage persisted for ${OUTAGE_MINUTES}m and no user activity detected. Initiating safe shutdown."
    systemctl poweroff
  fi
}

main